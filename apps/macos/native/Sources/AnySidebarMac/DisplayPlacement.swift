import Foundation
struct DisplayPlacement {
    static func panel(size:NSSize,anchor:NSRect,visible:NSRect)->NSRect {
        let margin:CGFloat=12,gap:CGFloat=12
        let width=min(size.width,visible.width-2*margin),height=min(size.height,visible.height-2*margin)
        let preferredX=anchor.maxX+gap+width <= visible.maxX-margin ? anchor.maxX+gap:anchor.minX-gap-width
        let x=max(visible.minX+margin,min(preferredX,visible.maxX-margin-width))
        let y=max(visible.minY+margin,min(anchor.maxY-height,visible.maxY-margin-height))
        return NSRect(x:x,y:y,width:width,height:height)
    }
}
