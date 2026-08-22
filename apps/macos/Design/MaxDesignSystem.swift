import SwiftUI

struct MaxPalette: Sendable {
  let accent: Color
  let secondaryAccent: Color
  let backgroundTop: Color
  let backgroundBottom: Color
  let textPrimary: Color
  let textSecondary: Color
  let solidSurface: Color

  static func palette(for theme: AppTheme, colorScheme: ColorScheme) -> MaxPalette {
    switch theme {
    case .light:
      MaxPalette(
        accent: Color(red: 0.16, green: 0.38, blue: 0.98),
        secondaryAccent: Color(red: 0.35, green: 0.73, blue: 1.0),
        backgroundTop: Color(red: 0.91, green: 0.95, blue: 1.0),
        backgroundBottom: Color(red: 0.78, green: 0.87, blue: 0.98),
        textPrimary: .primary,
        textSecondary: .secondary,
        solidSurface: Color.white.opacity(0.94)
      )
    case .dark:
      MaxPalette(
        accent: Color(red: 0.49, green: 0.66, blue: 1.0),
        secondaryAccent: Color(red: 0.59, green: 0.36, blue: 0.98),
        backgroundTop: Color(red: 0.035, green: 0.045, blue: 0.08),
        backgroundBottom: Color(red: 0.09, green: 0.06, blue: 0.16),
        textPrimary: .primary,
        textSecondary: .secondary,
        solidSurface: Color(red: 0.10, green: 0.11, blue: 0.17).opacity(0.96)
      )
    case .spectrum:
      MaxPalette(
        accent: Color(red: 1.0, green: 0.25, blue: 0.56),
        secondaryAccent: Color(red: 0.16, green: 0.83, blue: 0.94),
        backgroundTop: Color(red: 0.12, green: 0.04, blue: 0.23),
        backgroundBottom: Color(red: 0.04, green: 0.16, blue: 0.22),
        textPrimary: .primary,
        textSecondary: .secondary,
        solidSurface: Color(red: 0.12, green: 0.08, blue: 0.20).opacity(0.96)
      )
    case .clouds:
      MaxPalette(
        accent: Color(red: 0.15, green: 0.49, blue: 0.92),
        secondaryAccent: Color(red: 0.48, green: 0.80, blue: 1.0),
        backgroundTop: Color(red: 0.67, green: 0.85, blue: 1.0),
        backgroundBottom: Color(red: 0.90, green: 0.95, blue: 1.0),
        textPrimary: .primary,
        textSecondary: .secondary,
        solidSurface: Color.white.opacity(0.94)
      )
    case .council:
      MaxPalette(
        accent: Color(red: 0.88, green: 0.69, blue: 0.25),
        secondaryAccent: Color(red: 0.58, green: 0.39, blue: 0.16),
        backgroundTop: Color(red: 0.11, green: 0.075, blue: 0.045),
        backgroundBottom: Color(red: 0.24, green: 0.13, blue: 0.055),
        textPrimary: .primary,
        textSecondary: .secondary,
        solidSurface: Color(red: 0.20, green: 0.13, blue: 0.07).opacity(0.97)
      )
    case .max:
      MaxPalette(
        accent: Color(red: 0.35, green: 0.48, blue: 1.0),
        secondaryAccent: Color(red: 0.66, green: 0.34, blue: 0.96),
        backgroundTop: colorScheme == .dark
          ? Color(red: 0.035, green: 0.055, blue: 0.13)
          : Color(red: 0.78, green: 0.86, blue: 1.0),
        backgroundBottom: colorScheme == .dark
          ? Color(red: 0.14, green: 0.055, blue: 0.19)
          : Color(red: 0.94, green: 0.88, blue: 1.0),
        // Semantic foreground colors participate in Tahoe's material vibrancy.
        // Fixed white/black colors lose contrast when Liquid Glass shifts from
        // the dark atmosphere behind it to a light, elevated glass surface.
        textPrimary: .primary,
        textSecondary: .secondary,
        solidSurface: colorScheme == .dark
          ? Color(red: 0.10, green: 0.10, blue: 0.18).opacity(0.96)
          : Color.white.opacity(0.94)
      )
    }
  }
}

enum MaxCopy {
  static func text(_ key: String, language: AppLanguage) -> String {
    if language == .english { return english[key] ?? key }
    return arabic[key] ?? english[key] ?? key
  }

  private static let english: [String: String] = [
    "vault": "Vault",
    "library": "Library",
    "shared": "Shared",
    "chats": "Chats",
    "profile": "Profile",
    "memories": "Memories",
    "plugins": "Plugins",
    "search": "Search",
    "upload": "Upload",
    "transfers": "Transfers",
    "settings": "Settings",
    "signOut": "Sign Out",
    "welcome": "Your private media universe",
    "continue": "Continue to Max",
    "email": "Email",
    "password": "Password",
    "signIn": "Sign In",
    "demo": "Explore Demo",
    "all": "All",
    "video": "Videos",
    "image": "Images",
    "saved": "Saved",
    "ratings": "Ratings",
    "offline": "Offline",
    "collections": "Collections",
    "trash": "Trash",
    "overview": "Overview",
    "files": "Files",
    "spaces": "Spaces",
    "newMessage": "New message",
    "messagePlaceholder": "Message",
    "editProfile": "Edit profile",
    "appearance": "Appearance",
    "language": "Language",
    "privacy": "Privacy",
    "downloads": "Downloads",
    "server": "Server",
    "security": "Double Lock",
    "general": "General",
    "advanced": "Advanced",
    "done": "Done",
    "cancel": "Cancel",
    "save": "Save",
    "share": "Share",
    "download": "Download",
    "rate": "Rate",
    "restore": "Restore",
    "delete": "Delete",
    "featureParity": "iPhone feature parity, adapted for the Mac",
    "localDemo": "Deterministic local demo — no account or network required",
  ]

  private static let arabic: [String: String] = [
    "vault": "الخزنة",
    "library": "المكتبة",
    "shared": "المشترك",
    "chats": "المحادثات",
    "profile": "الملف الشخصي",
    "memories": "الذكريات",
    "plugins": "الإضافات",
    "search": "بحث",
    "upload": "رفع",
    "transfers": "التحويلات",
    "settings": "الإعدادات",
    "signOut": "تسجيل الخروج",
    "welcome": "عالم وسائطك الخاص",
    "continue": "متابعة إلى Max",
    "email": "البريد الإلكتروني",
    "password": "كلمة المرور",
    "signIn": "تسجيل الدخول",
    "demo": "استكشاف النسخة التجريبية",
    "all": "الكل",
    "video": "الفيديو",
    "image": "الصور",
    "saved": "المحفوظات",
    "ratings": "التقييمات",
    "offline": "دون اتصال",
    "collections": "المجموعات",
    "trash": "المحذوفات",
    "overview": "نظرة عامة",
    "files": "الملفات",
    "spaces": "المساحات",
    "newMessage": "رسالة جديدة",
    "messagePlaceholder": "رسالة",
    "editProfile": "تعديل الملف الشخصي",
    "appearance": "المظهر",
    "language": "اللغة",
    "privacy": "الخصوصية",
    "downloads": "التنزيلات",
    "server": "الخادم",
    "security": "القفل المزدوج",
    "general": "عام",
    "advanced": "متقدم",
    "done": "تم",
    "cancel": "إلغاء",
    "save": "حفظ",
    "share": "مشاركة",
    "download": "تنزيل",
    "rate": "تقييم",
    "restore": "استعادة",
    "delete": "حذف",
    "featureParity": "ميزات الآيفون نفسها بتوزيع ملائم للماك",
    "localDemo": "نسخة محلية ثابتة — لا تحتاج حسابًا أو شبكة",
  ]
}

struct MaxAtmosphere: View {
  let palette: MaxPalette
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [palette.backgroundTop, palette.backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Circle()
        .fill(palette.accent.opacity(0.30))
        .frame(width: 520, height: 520)
        .blur(radius: 90)
        .offset(x: -330, y: -280)

      Circle()
        .fill(palette.secondaryAccent.opacity(0.28))
        .frame(width: 460, height: 460)
        .blur(radius: 100)
        .offset(x: 390, y: 290)
    }
    .ignoresSafeArea()
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: palette.accent)
  }
}

struct GlassCard<Content: View>: View {
  let tint: Color
  let cornerRadius: CGFloat
  let content: Content
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  init(
    tint: Color = .clear,
    cornerRadius: CGFloat = 22,
    @ViewBuilder content: () -> Content
  ) {
    self.tint = tint
    self.cornerRadius = cornerRadius
    self.content = content()
  }

  var body: some View {
    if reduceTransparency {
      content
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    } else {
      content
        .glassEffect(.regular.tint(tint.opacity(0.14)), in: .rect(cornerRadius: cornerRadius))
    }
  }
}

struct MediaArtwork: View {
  let item: MediaItem
  var compact = false

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(hue: item.hue, saturation: 0.72, brightness: 0.96),
          Color(hue: (item.hue + 0.13).truncatingRemainder(dividingBy: 1), saturation: 0.82, brightness: 0.36),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Circle()
        .fill(Color.white.opacity(0.20))
        .frame(width: compact ? 64 : 160, height: compact ? 64 : 160)
        .blur(radius: compact ? 12 : 30)
        .offset(x: compact ? 25 : 70, y: compact ? -18 : -55)

      Image(systemName: item.symbol)
        .font(.system(size: compact ? 22 : 48, weight: .semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
    .clipped()
    .accessibilityHidden(true)
  }
}

struct EmptyStateView: View {
  let symbol: String
  let title: String
  let message: String

  var body: some View {
    ContentUnavailableView(title, systemImage: symbol, description: Text(message))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension AppTheme {
  var localizedName: String {
    switch self {
    case .max: "Max"
    case .light: "Light"
    case .dark: "Dark"
    case .spectrum: "Spectrum"
    case .clouds: "Clouds"
    case .council: "Council"
    }
  }

  var preferredColorScheme: ColorScheme? {
    switch self {
    case .light, .clouds: .light
    case .dark, .spectrum, .council: .dark
    case .max: nil
    }
  }
}
