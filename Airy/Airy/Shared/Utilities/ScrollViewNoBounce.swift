//
//  ScrollViewNoBounce.swift
//  Airy
//
//  Modifier to disable scroll bounce on SwiftUI ScrollView.
//

import SwiftUI
import UIKit

struct ScrollViewNoBounceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ScrollViewBounceDisabler())
    }
}

private struct ScrollViewBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> BounceDisablerView {
        BounceDisablerView()
    }

    func updateUIView(_ uiView: BounceDisablerView, context: Context) {
        uiView.disableBounceOnScrollViews()
    }
}

private class BounceDisablerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        disableBounceOnScrollViews()
    }

    func disableBounceOnScrollViews() {
        DispatchQueue.main.async { [weak self] in
            self?.findAndDisableBounce()
        }
    }

    private func findAndDisableBounce() {
        var v: UIView? = self.superview
        while let view = v {
            if let scrollView = view as? UIScrollView {
                scrollView.bounces = false
                return
            }
            v = view.superview
        }
    }
}

extension View {
    func scrollViewNoBounce() -> some View {
        modifier(ScrollViewNoBounceModifier())
    }
}
