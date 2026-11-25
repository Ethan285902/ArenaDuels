//
//  HUDExtras.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 26/11/2026.
//

import SwiftUI

struct Toast: Equatable {
    let title: String
    let detail: String
}

/// A banner that slides in when a trophy is unlocked.
struct TrophyToast: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("TROPHY UNLOCKED")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .opacity(0.7)
                Text(toast.title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                Text(toast.detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
    }
}

/// Flashes red around the screen when an enemy sniper is aiming at you, with an arrow showing where they are.
/// `bearing` is the direction of the sniper: 0 = straight ahead, positive = to your right (radians).
struct SniperWarning: View {
    let bearing: Double

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 16)
            ZStack {
                Rectangle()
                    .strokeBorder(Color.red.opacity(0.25 + 0.45 * pulse), lineWidth: 18)
                VStack(spacing: 2) {
                    Image(systemName: "arrowtriangle.up.fill").font(.system(size: 34))
                    Text("SNIPER").font(.system(size: 14, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Color.red.opacity(0.6 + 0.4 * pulse))
                .offset(y: -150)
                .rotationEffect(.radians(bearing))
            }
        }
        .allowsHitTesting(false)
    }
}
