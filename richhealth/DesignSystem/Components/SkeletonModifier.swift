import SwiftUI

/// Loading placeholder. Replaces Android Skeleton.java. Usage: `.skeleton(isActive: vm.isLoading)`.
struct SkeletonModifier: ViewModifier {
    var isActive: Bool
    func body(content: Content) -> some View {
        content.redacted(reason: isActive ? .placeholder : [])
    }
}

extension View {
    func skeleton(isActive: Bool) -> some View { modifier(SkeletonModifier(isActive: isActive)) }
}
