import SwiftUI

extension Color {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let appBackgroundStart = Color.dynamic(
        light: UIColor(red: 0.99, green: 0.96, blue: 0.90, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1)
    )
    static let appBackgroundMid = Color.dynamic(
        light: UIColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.08, blue: 0.07, alpha: 1)
    )
    static let appBackgroundEnd = Color.dynamic(
        light: UIColor(red: 0.91, green: 0.88, blue: 0.80, alpha: 1),
        dark: UIColor(red: 0.06, green: 0.05, blue: 0.05, alpha: 1)
    )
    static let cardBackground = Color.dynamic(
        light: UIColor.white.withAlphaComponent(0.92),
        dark: UIColor(red: 0.14, green: 0.13, blue: 0.12, alpha: 0.9)
    )
    static let cardStroke = Color.dynamic(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.08)
    )
    static let dayCardBackground = Color.dynamic(
        light: UIColor.white.withAlphaComponent(0.9),
        dark: UIColor(red: 0.19, green: 0.18, blue: 0.17, alpha: 0.95)
    )
    static let dayCardStroke = Color.dynamic(
        light: UIColor.black.withAlphaComponent(0.07),
        dark: UIColor.white.withAlphaComponent(0.14)
    )
    static let dayItemBackground = Color.dynamic(
        light: UIColor.white.withAlphaComponent(0.96),
        dark: UIColor(red: 0.25, green: 0.24, blue: 0.23, alpha: 1)
    )
    static let fieldBackground = Color.dynamic(
        light: UIColor.white.withAlphaComponent(0.96),
        dark: UIColor(red: 0.20, green: 0.19, blue: 0.18, alpha: 1)
    )
    static let accentGold = Color(red: 0.95, green: 0.71, blue: 0.26)
    static let planBlue = Color(red: 0.37, green: 0.56, blue: 0.99)
    static let travelCoral = Color(red: 1.0, green: 0.48, blue: 0.36)
    static let freeGreen = Color(red: 0.52, green: 0.76, blue: 0.54)
    static let protectedRed = Color(red: 0.88, green: 0.29, blue: 0.25)
    static let protectedYellow = Color(red: 0.96, green: 0.82, blue: 0.25)
    static var protectedStripeGradient: LinearGradient {
        let stripeWidth = 0.1
        var stops: [Gradient.Stop] = []
        var position = 0.0
        var useRed = true

        while position < 1 {
            let next = min(position + stripeWidth, 1)
            let color = useRed ? Color.protectedRed : Color.protectedYellow
            stops.append(.init(color: color, location: position))
            stops.append(.init(color: color, location: next))
            position = next
            useRed.toggle()
        }

        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum AppSurfaceStyle {
    static let primaryCardCornerRadius: CGFloat = 20

    static var settingsGroupBackground: Color {
        Color(UIColor.systemGroupedBackground)
    }

    static var settingsCardBackground: Color {
        Color(UIColor.secondarySystemGroupedBackground)
    }

    static var settingsChipBackground: Color {
        Color(UIColor.tertiarySystemGroupedBackground)
    }

    static var settingsSeparator: Color {
        Color(UIColor.separator).opacity(0.22)
    }

    static var cardFill: AnyShapeStyle {
        if #available(iOS 26.0, *) {
            return AnyShapeStyle(.thinMaterial)
        }
        return AnyShapeStyle(Color.cardBackground)
    }

    static var dayCardFill: AnyShapeStyle {
        if #available(iOS 26.0, *) {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        return AnyShapeStyle(Color.dayCardBackground)
    }

    static var dayItemFill: AnyShapeStyle {
        if #available(iOS 26.0, *) {
            return AnyShapeStyle(.regularMaterial)
        }
        return AnyShapeStyle(Color.dayItemBackground)
    }

    static var fieldFill: AnyShapeStyle {
        if #available(iOS 26.0, *) {
            return AnyShapeStyle(.thinMaterial)
        }
        return AnyShapeStyle(Color.fieldBackground)
    }

    static var cardStroke: Color {
        if #available(iOS 26.0, *) {
            return Color.dynamic(
                light: UIColor.black.withAlphaComponent(0.08),
                dark: UIColor.white.withAlphaComponent(0.22)
            )
        }
        return Color.cardStroke
    }

    static var dayStroke: Color {
        if #available(iOS 26.0, *) {
            return Color.dynamic(
                light: UIColor.black.withAlphaComponent(0.07),
                dark: UIColor.white.withAlphaComponent(0.18)
            )
        }
        return Color.dayCardStroke
    }

    static var cardShadowColor: Color {
        if #available(iOS 26.0, *) {
            return Color.black.opacity(0.04)
        }
        return Color.black.opacity(0.08)
    }

    static var cardShadowRadius: CGFloat {
        if #available(iOS 26.0, *) {
            return 10
        }
        return 18
    }

    static var cardShadowYOffset: CGFloat {
        if #available(iOS 26.0, *) {
            return 5
        }
        return 12
    }

    static var fieldShadowColor: Color {
        if #available(iOS 26.0, *) {
            return Color.black.opacity(0.03)
        }
        return Color.black.opacity(0.08)
    }

    static var fieldShadowRadius: CGFloat {
        if #available(iOS 26.0, *) {
            return 6
        }
        return 10
    }

    static var fieldShadowYOffset: CGFloat {
        if #available(iOS 26.0, *) {
            return 3
        }
        return 6
    }

    static var primaryButtonFill: Color {
        if #available(iOS 26.0, *) {
            return Color.dynamic(
                light: UIColor.systemGray5.withAlphaComponent(0.95),
                dark: UIColor.systemGray4.withAlphaComponent(0.55)
            )
        }
        return Color.black.opacity(0.9)
    }

    static var primaryButtonForeground: Color {
        if #available(iOS 26.0, *) {
            return .primary
        }
        return .white
    }

    static var modalScrim: Color {
        if #available(iOS 26.0, *) {
            return Color.black.opacity(0.08)
        }
        return Color.black.opacity(0.15)
    }
}

struct AppGradientBackground: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color.appBackgroundStart, Color.appBackgroundMid, Color.appBackgroundEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(fill)
            .foregroundColor(foreground)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct OutlinePillButtonStyle: ButtonStyle {
    var stroke: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.clear)
            .foregroundColor(foreground)
            .overlay(
                Capsule()
                    .stroke(stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct StatusDot: View {
    var color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }
}

struct ProtectedStripeDot: View {
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Color.protectedStripeGradient)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(AppSurfaceStyle.cardStroke, lineWidth: 1)
            )
    }
}

struct TagPill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.16))
            .clipShape(Capsule())
    }
}

struct CardContainer<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous)
                    .fill(AppSurfaceStyle.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous)
                    .stroke(AppSurfaceStyle.cardStroke, lineWidth: 1)
            )
            .shadow(
                color: AppSurfaceStyle.cardShadowColor,
                radius: AppSurfaceStyle.cardShadowRadius,
                x: 0,
                y: AppSurfaceStyle.cardShadowYOffset
            )
    }
}

struct PillTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(AppSurfaceStyle.fieldFill)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppSurfaceStyle.cardStroke.opacity(0.9), lineWidth: 1)
            )
            .shadow(
                color: AppSurfaceStyle.fieldShadowColor,
                radius: AppSurfaceStyle.fieldShadowRadius,
                x: 0,
                y: AppSurfaceStyle.fieldShadowYOffset
            )
    }
}
