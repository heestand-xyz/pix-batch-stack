import AppKit
import RenderKit
import PixelKit

frameLoopRenderThread = .background
PixelKit.main.render.engine.renderMode = .manual
PixelKit.main.render.bits = ._16

let args = CommandLine.arguments
let fm = FileManager.default

let callURL: URL = URL(fileURLWithPath: args[0])

func getURL(_ path: String) -> URL {
    if path.starts(with: "/") {
        return URL(fileURLWithPath: path)
    }
    if path.starts(with: "~/") {
        let docsURL: URL = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docsURL.deletingLastPathComponent().appendingPathComponent(path.replacingOccurrences(of: "~/", with: ""))
    }
    return callURL.appendingPathComponent(path)
}

let argCount: Int = 4
guard args.count == argCount + 1 else {
    print("pix-batch-stack <count> <resolution> <input-folder> <output-folder>")
    exit(EXIT_FAILURE)
}

guard let batchGroupCount: Int = Int( args[1]) else {
    print("count format: \"10\"")
    exit(EXIT_FAILURE)
}

let resArg: String = args[2]
let resParts: [String] = resArg.components(separatedBy: "x")
guard resParts.count == 2,
      let resWidth: Int = Int(resParts[0]),
      let resHeight: Int = Int(resParts[1]) else {
    print("resolution format: \"1000x1000\"")
    exit(EXIT_FAILURE)
}
let resolution: Resolution = .custom(w: resWidth, h: resHeight)

let inputFolderURL: URL = getURL(args[3])
var inputFolderIsDir: ObjCBool = false
let inputFolderExists: Bool = fm.fileExists(atPath: inputFolderURL.path, isDirectory: &inputFolderIsDir)
guard inputFolderExists && inputFolderIsDir.boolValue else {
    print("input needs to be a folder")
    print(inputFolderURL.path)
    exit(EXIT_FAILURE)
}

let outputFolderURL: URL = getURL(args[4])
var outputFolderIsDir: ObjCBool = false
let outputFolderExists: Bool = fm.fileExists(atPath: outputFolderURL.path, isDirectory: &outputFolderIsDir)
if outputFolderExists {
    guard outputFolderIsDir.boolValue else {
        print("output needs to be a folder")
        print(outputFolderURL.path)
        exit(EXIT_FAILURE)
    }
} else {
    try! fm.createDirectory(at: outputFolderURL, withIntermediateDirectories: true, attributes: nil)
}


// MARK: - PIXs

let backgroundPix = ColorPIX(at: resolution)
backgroundPix.color = .black

func average(images: [NSImage]) -> NSImage {
    let blendsPix = BlendsPIX()
    blendsPix.blendMode = .avg
    blendsPix.inputs = [backgroundPix]
    let finalPix = blendsPix//._gamma(0.75)
    let imagePixs: [ImagePIX] = images.map { image in
        let imagePix = ImagePIX()
        imagePix.image = image
        blendsPix.inputs.append(imagePix)
        return imagePix
    }
    print("average will render")
    var outImg: NSImage!
    let group = DispatchGroup()
    group.enter()
    try! PixelKit.main.render.engine.manuallyRender {
        guard let img: NSImage = finalPix.renderedImage else {
            print("average render failed")
            exit(EXIT_FAILURE)
        }
        outImg = img
        group.leave()
    }
    group.wait()
    print("average did render")
    finalPix.destroy()
    blendsPix.destroy()
    imagePixs.forEach { imagePix in
        imagePix.destroy()
    }
    return outImg
}

var groupImages: [NSImage] = []

// MARK: - Images

let fileNames: [String] = try! fm.contentsOfDirectory(atPath: inputFolderURL.path).sorted()
let count: Int = fileNames.count
var index: Int = 0
for (i, fileName) in fileNames.enumerated() {

    guard fileName != ".DS_Store" else { continue }
    let fileURL: URL = inputFolderURL.appendingPathComponent(fileName)
    let fileExtension: String = fileURL.pathExtension.lowercased()
    guard ["png", "jpg", "tiff"].contains(fileExtension) else {
        print("\(i + 1)/\(count) non image \"\(fileName)\"")
        continue
    }
    
    guard let image: NSImage = NSImage(contentsOf: fileURL) else {
        print("error \"\(fileName)\"")
        continue
    }
    print("\(i + 1)/\(count) image \"\(fileName)\" \(Int(image.size.width))x\(Int(image.size.height))")
    
    groupImages.append(image)
    
    let atBatchGroupEnd: Bool = i % batchGroupCount == batchGroupCount - 1 || i == count - 1
    if atBatchGroupEnd {
        
        let saveURL = outputFolderURL.appendingPathComponent("stack_\(index).png")
        
        let saveFileExists: Bool = fm.fileExists(atPath: saveURL.path)
        if saveFileExists {
            print("\(i + 1)/\(count) skip \"\(fileName)\"")
            groupImages = []
            continue
        }
        
        let averagedImage: NSImage = average(images: groupImages)
        
        let bitmap = NSBitmapImageRep(data: averagedImage.tiffRepresentation!)!
        let data: Data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: saveURL)
        
        groupImages = []
        index += 1

    }

}

print("done!")
