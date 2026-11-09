import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import ReadingCore
public final class FileAttachmentStore: AttachmentStore, @unchecked Sendable {
    public let root: URL
    private let lock=NSLock()
    public init(root: URL) throws {
        self.root=root
        for name in ["images","thumbnails","temporary"] {try FileManager.default.createDirectory(at:root.appendingPathComponent(name),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}
    }
    public static func digest(_ data: Data) -> String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
    public func persist(png: Data, source: SourceInfo) throws -> ImageAsset {
        lock.lock();defer{lock.unlock()}
        guard png.count <= 10*1024*1024 else{throw AppFault("IMAGE_TOO_LARGE","截图超过 10 MiB，请截取更小区域。")}
        guard let src=CGImageSourceCreateWithData(png as CFData,nil), CGImageSourceGetType(src) == UTType.png.identifier as CFString,
              let properties=CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [CFString:Any],let w=properties[kCGImagePropertyPixelWidth] as? Int,let h=properties[kCGImagePropertyPixelHeight] as? Int,w>0,h>0 else{throw AppFault("CAPTURE_FAILED","截图格式无效。")}
        let id=newID(),key="images/\(id).png",thumb="thumbnails/\(id).png"
        try png.write(to:root.appendingPathComponent(key),options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:root.appendingPathComponent(key).path)
        if let image=CGImageSourceCreateThumbnailAtIndex(src,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:240,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary),let dest=CGImageDestinationCreateWithURL(root.appendingPathComponent(thumb) as CFURL,UTType.png.identifier as CFString,1,nil) {CGImageDestinationAddImage(dest,image,nil);guard CGImageDestinationFinalize(dest) else{throw AppFault.storage};try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:root.appendingPathComponent(thumb).path)}
        return ImageAsset(id:id,source:source,width:w,height:h,byteLength:png.count,sha256:Self.digest(png),storageKey:key,thumbnailKey:FileManager.default.fileExists(atPath:root.appendingPathComponent(thumb).path) ? thumb:nil)
    }
    private func checkedURL(_ key: String) throws -> URL {
        guard !key.hasPrefix("/"),!key.split(separator:"/").contains(".."),key.split(separator:"/").count == 2 else{throw AppFault("IMAGE_MISSING","截图路径无效。")}
        let url=root.appendingPathComponent(key).standardizedFileURL
        guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path+"/") else{throw AppFault("IMAGE_MISSING","截图不可用。")};return url
    }
    public func read(_ asset: ImageAsset) throws -> Data {
        let url=try checkedURL(asset.storageKey)
        guard let data=try? Data(contentsOf:url,options:.mappedIfSafe),data.count == asset.byteLength,Self.digest(data) == asset.sha256 else{throw AppFault("IMAGE_MISSING","原截图缺失或已损坏，请重新截取。")};return data
    }
    public func preview(_ asset: ImageAsset,thumbnail: Bool) throws -> Data {
        if thumbnail,let key=asset.thumbnailKey,let data=try? Data(contentsOf:checkedURL(key)){return data};return try read(asset)
    }
    public func removeUnreferenced(keeping: Set<ID>) throws {
        lock.lock();defer{lock.unlock()}
        for name in ["images","thumbnails","temporary"] {
            for url in try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent(name),includingPropertiesForKeys:nil) {
                if name == "temporary" || !keeping.contains(url.deletingPathExtension().lastPathComponent) {try FileManager.default.removeItem(at:url)}
            }
        }
    }
}
