import AppKit
import SwiftUI

/// 状态栏图标的手绘兜底形状：把 App 图标的轮廓简化到菜单栏尺寸。
/// 正常路径用的是用户提供的 StatusIcon.png（见 StatusItemImage）。
///
/// App 图标是「圆角方块 + 卡片 + 光标」，但把它整个缩到 18pt 只会得到一团蓝块
/// （渲染实测过）。菜单栏版只保留能读出来的两样：**圆角方块的轮廓**和**光标**——
/// 卡片上那些细线在这个尺寸下必然糊掉，只能舍掉。
///
/// 画成 SwiftUI 视图后再转成 template 图片交给系统，这样浅色/深色菜单栏、
/// 以及选中时的反白都由系统负责，不会出现"深色模式下还是黑图标"这种问题。
struct StatusItemGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // 方块与光标要**彻底分开**：贴着放时两者的边会粘成一坨
            // （渲染实测过两次）。所以方块缩到左上、光标退到右下，中间留空隙。
            let stroke = side * 0.08
            let box = side * 0.58

            ZStack {
                RoundedRectangle(cornerRadius: box * 0.32, style: .continuous)
                    .strokeBorder(lineWidth: stroke)
                    .frame(width: box, height: box)
                    .offset(x: -side * 0.15, y: -side * 0.15)

                Image(systemName: "cursorarrow")
                    .font(.system(size: side * 0.4, weight: .medium))
                    .offset(x: side * 0.22, y: side * 0.22)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// ImageRenderer 是 MainActor 隔离的（兜底路径会用到），所以整个枚举都标上，
/// 这样 static let 也只在主线程上初始化。
@MainActor
enum StatusItemImage {
    /// 菜单栏图标的逻辑尺寸。
    ///
    /// 用 18 而不是 16：用户提供的图标是一张「卡片 + 线条 + 光标」，
    /// 渲染实测 16pt 下三样东西会挤成一团，18pt 才勉强读得出，20pt 最清楚。
    /// 系统实际给多少由菜单栏决定，这里定的是我们提交的逻辑尺寸。
    private static let size: CGFloat = 18

    /// 用户提供的形状，已经转成菜单栏要的「黑 + alpha」模板。
    static let normal: NSImage = make()

    private static func make() -> NSImage {
        // 手绘的兜底形状：万一资源缺失也不至于没有图标
        func fallback() -> NSImage {
            let renderer = ImageRenderer(
                content: StatusItemGlyph().frame(width: size, height: size).foregroundStyle(.black)
            )
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let image = NSImage(cgImage: cg, size: NSSize(width: size, height: size))
                image.isTemplate = true
                return image
            }
            return NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: "RightKit")
                ?? NSImage()
        }

        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            DiagnosticsLog.log("status icon resource missing; using the drawn fallback")
            return fallback()
        }

        // 512px 的源图按逻辑尺寸提交，位图本身留给系统在 Retina 上取用。
        image.size = NSSize(width: size, height: size)
        // 关键：template 让系统负责配色（浅色/深色菜单栏、选中反白）
        image.isTemplate = true
        return image
    }
}
