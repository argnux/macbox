import SwiftUI

enum AppUI {
    static let pagePadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 16
    static let controlSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 8
    static let toolbarButtonHeight: CGFloat = 36
    static let iconButtonSize = CGSize(width: 36, height: 32)
}

struct PageHeader<Actions: View>: View {
    var title: String
    var subtitle: String?
    var actions: Actions

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppUI.controlSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 16)

            actions
        }
    }
}

extension PageHeader where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.actions = EmptyView()
    }
}

struct AppPanel<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AppUI.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppUI.cornerRadius)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
            )
    }
}

struct SectionHeader<Actions: View>: View {
    var title: String
    var subtitle: String?
    var actions: Actions

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppUI.controlSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)
            actions
        }
    }
}

extension SectionHeader where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.actions = EmptyView()
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String?

    init(systemImage: String, title: String, message: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusBadge: View {
    var title: String
    var systemImage: String?
    var color: Color

    init(_ title: String, systemImage: String? = nil, color: Color = .secondary) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct SheetHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    func toolbarButtonFrame() -> some View {
        frame(minHeight: AppUI.toolbarButtonHeight)
    }

    func iconButtonFrame() -> some View {
        frame(width: AppUI.iconButtonSize.width, height: AppUI.iconButtonSize.height)
    }
}
