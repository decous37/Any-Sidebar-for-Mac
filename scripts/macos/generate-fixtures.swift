import AppKit
import CoreGraphics
import Foundation
let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let file=output.appendingPathComponent("reading-fixture.pdf")
var box=CGRect(x:0,y:0,width:612,height:792)
let context=CGContext(file as CFURL,mediaBox:&box,nil)!
context.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
let paragraphs=["Any Sidebar 阅读测试", "选择这一段文字，助手应自动保留引用。", "This paragraph explains how a cache avoids repeated computation.", "A cache stores completed results. It does not replace validation.", "输入框获得焦点后，引用仍应保留。", "图表示例：样本数量 10、20、30；耗时 8、5、3 毫秒。"]
for (i,line) in paragraphs.enumerated(){(line as NSString).draw(at:NSPoint(x:48,y:720-i*70),withAttributes:[.font:NSFont.systemFont(ofSize:i==0 ? 24:16),.foregroundColor:NSColor.black])}
NSGraphicsContext.restoreGraphicsState();context.endPDFPage();context.closePDF()
print(file.path)
