import AppKit
import RenderKit
import PixelKit

frameLoopRenderThread = .background
PixelKit.main.render.engine.renderMode = .manual
PixelKit.main.render.bits = ._16

let args = CommandLine.arguments
let fm = FileManager.default

let batchGroupCount: Int = 16

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

let argCount: Int = 3
guard args.count == argCount + 1 else {
    print("pix-batch-stack <resolution> <input-folder> <output-image>")
    exit(EXIT_FAILURE)
}

let resArg: String = args[1]
let resParts: [String] = resArg.components(separatedBy: "x")
guard resParts.count == 2,
      let resWidth: Int = Int(resParts[0]),
      let resHeight: Int = Int(resParts[1]) else {
    print("resolution format: \"1000x1000\"")
    exit(EXIT_FAILURE)
}
let resolution: Resolution = .custom(w: resWidth, h: resHeight)

let folderURL: URL = getURL(args[2])
var folderIsDir: ObjCBool = false
let folderExists: Bool = fm.fileExists(atPath: folderURL.path, isDirectory: &folderIsDir)
guard folderExists && folderIsDir.boolValue else {
    print("input needs to be a folder")
    print(folderURL.path)
    exit(EXIT_FAILURE)
}

let saveURL: URL = getURL(args[3])
var saveIsDir: ObjCBool = false
let saveExists: Bool = fm.fileExists(atPath: saveURL.path, isDirectory: &saveIsDir)
let saveExtension: String = saveURL.pathExtension.lowercased()
guard !saveIsDir.boolValue && ["png", "jpg"].contains(saveExtension) else {
    print("output needs to be a .png or .jpg file")
    print(saveURL.path)
    exit(EXIT_FAILURE)
}


// MARK: - PIXs

let backgroundPix = ColorPIX(at: resolution)
backgroundPix.color = .black

func average(images: [NSImage]) -> NSImage {
    let blendsPix = BlendsPIX()
    blendsPix.blendMode = .avg
    blendsPix.inputs = [backgroundPix]
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
        guard let img: NSImage = blendsPix.renderedImage else {
            print("average render failed")
            exit(EXIT_FAILURE)
        }
        outImg = img
        group.leave()
    }
    group.wait()
    print("average did render")
    blendsPix.destroy()
    imagePixs.forEach { imagePix in
        imagePix.destroy()
    }
    return outImg
}

var groupImages: [NSImage] = []
var averagedImages: [NSImage] = []

// MARK: - Images

let fileNames: [String] = try! fm.contentsOfDirectory(atPath: folderURL.path).sorted()
let count: Int = fileNames.count
for (i, fileName) in fileNames.enumerated() {

    guard fileName != ".DS_Store" else { continue }
    let fileURL: URL = folderURL.appendingPathComponent(fileName)
    let fileExtension: String = fileURL.pathExtension.lowercased()
    guard ["png", "jpg", "tiff"].contains(fileExtension) else {
        print("\(i + 1)/\(count) non image \"\(fileName)\"")
        continue
    }
    let saveFileExists: Bool = fm.fileExists(atPath: saveURL.path)
    if saveFileExists {
        print("\(i + 1)/\(count) skip \"\(fileName)\"")
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
        let averagedImage: NSImage = average(images: groupImages)
        averagedImages.append(averagedImage)
        groupImages = []
    }

}

let finalImage: NSImage = average(images: averagedImages)

let finalImagePix = ImagePIX()
finalImagePix.image = finalImage

let finalPix: PIX & NODEOut = finalImagePix._gamma(0.5)

// MARK: - Render

print("will render")
var outImg: NSImage!
let group = DispatchGroup()
group.enter()
try! PixelKit.main.render.engine.manuallyRender {
    guard let img: NSImage = finalPix.renderedImage else {
        print("render failed")
        exit(EXIT_FAILURE)
    }
    outImg = img
    print("did render")
    group.leave()
}
group.wait()

let bitmap = NSBitmapImageRep(data: outImg.tiffRepresentation!)!
var data: Data!
if saveExtension == "png" {
    data = bitmap.representation(using: .png, properties: [:])!
} else if saveExtension == "jpg" {
    data = bitmap.representation(using: .jpeg, properties: [.compressionFactor:0.8])!
}
try data.write(to: saveURL)

print("done!")
