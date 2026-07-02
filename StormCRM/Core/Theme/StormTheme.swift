import SwiftUI

/// Storm Sprinklers brand tokens — aligned with crm/src/lib/branding.ts
enum StormTheme {
    static let navy = Color(hex: "#102341")!
    static let sky = Color(hex: "#4C9BC8")!
    static let coral = Color(hex: "#F17388")!
    static let ice = Color(hex: "#C2E4F0")!
    static let page = Color(hex: "#F8FAFC")!
    static let success = Color(hex: "#16A34A")!
}

extension Color {
    init?(hex: String?) {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

struct StormCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(StormTheme.ice.opacity(0.8), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: StormTheme.navy.opacity(0.06), radius: 8, y: 2)
    }
}

struct StormSectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(StormTheme.sky)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(StormTheme.navy)
        }
    }
}

struct StormPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(StormTheme.coral.opacity(configuration.isPressed ? 0.85 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StormSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(StormTheme.ice.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(StormTheme.navy)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    @ViewBuilder
    func stormButtonStyle(primary: Bool) -> some View {
        if primary {
            buttonStyle(StormPrimaryButtonStyle())
        } else {
            buttonStyle(StormSecondaryButtonStyle())
        }
    }
}

struct StormBadge: View {
    let text: String
    var style: Style = .neutral

    enum Style {
        case neutral, accent, success, warning
    }

    var body: some View {
        Text(text.replacingOccurrences(of: "_", with: " "))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch style {
        case .neutral: StormTheme.ice.opacity(0.55)
        case .accent: StormTheme.coral.opacity(0.15)
        case .success: StormTheme.success.opacity(0.15)
        case .warning: Color.orange.opacity(0.15)
        }
    }

    private var foreground: Color {
        switch style {
        case .neutral: StormTheme.navy
        case .accent: StormTheme.coral
        case .success: StormTheme.success
        case .warning: .orange
        }
    }
}

struct NamedColorChip: View {
    let person: NamedColor

    var body: some View {
        HStack(spacing: 8) {
            EmployeeAvatar(person: person, size: 32)
            Text(person.name)
                .font(.subheadline)
        }
    }
}

struct AsyncLogoImage: View {
    let urlString: String?
    var height: CGFloat = 44

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    StormLogoMark()
                default:
                    ProgressView()
                }
            }
            .frame(height: height)
        } else {
            StormLogoMark()
        }
    }
}

struct StormLogoMark: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.fill")
                .foregroundStyle(StormTheme.coral)
            Text("Storm Sprinklers")
                .font(.title3.weight(.bold))
                .foregroundStyle(StormTheme.navy)
        }
    }
}
