//
//  GunModels.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 24/11/2026.
//

import SceneKit
import AppKit

/// First-person weapon models: detailed parts, plus hands and forearms.
/// Every weapon is built facing -z, with its rear at the origin.
enum GunModels {
    static func build(_ index: Int, into gun: SCNNode, flash: SCNNode) {
        let steel = NSColor(red: 0.22, green: 0.23, blue: 0.27, alpha: 1)
        let dark = NSColor(white: 0.12, alpha: 1)
        let light = NSColor(white: 0.72, alpha: 1)
        let wood = NSColor(red: 0.55, green: 0.36, blue: 0.2, alpha: 1)
        let skin = NSColor(red: 0.95, green: 0.78, blue: 0.62, alpha: 1)
        let sleeve = NSColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1)
        let accents: [NSColor] = [.systemTeal, .systemOrange, .systemPurple, .systemYellow, .systemRed, .systemGray, .systemPink, .systemGreen, .systemIndigo, .systemBrown, .systemMint, .systemCyan, .systemRed, .systemOrange]
        let accent = accents[min(index, accents.count - 1)]
        let len = Weapon.all[index].gunLength

        func mat(_ color: NSColor, metal: Bool) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.specular.contents = NSColor(white: metal ? 0.9 : 0.3, alpha: 1)
            return m
        }
        func box(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat,
                 _ color: NSColor, metal: Bool = false, tilt: CGFloat = 0, chamfer: CGFloat = 0.01) {
            let g = SCNBox(width: sx, height: sy, length: sz, chamferRadius: chamfer)
            g.materials = [mat(color, metal: metal)]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(x, y, z)
            n.eulerAngles = SCNVector3(tilt, 0, 0)
            gun.addChildNode(n)
        }
        func cyl(_ r: CGFloat, _ length: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ color: NSColor) {
            let g = SCNCylinder(radius: r, height: length)
            g.radialSegmentCount = 20
            g.materials = [mat(color, metal: true)]
            let n = SCNNode(geometry: g)
            n.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)      // lay it along the barrel direction
            n.position = SCNVector3(x, y, z)
            gun.addChildNode(n)
        }
        func ball(_ r: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ color: NSColor) {
            let g = SCNSphere(radius: r)
            g.materials = [mat(color, metal: false)]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(x, y, z)
            gun.addChildNode(n)
        }
        /// A hand with a forearm reaching back towards the player. side: +1 right arm, -1 left arm.
        func hand(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, side: CGFloat) {
            box(0.06, 0.07, 0.09, x, y, z, skin, chamfer: 0.02)
            let g = SCNBox(width: 0.07, height: 0.07, length: 0.34, chamferRadius: 0.025)
            g.materials = [mat(sleeve, metal: false)]
            let arm = SCNNode(geometry: g)
            arm.position = SCNVector3(x + side * 0.05, y - 0.1, z + 0.22)
            arm.eulerAngles = SCNVector3(0.38, side * 0.18, 0)
            gun.addChildNode(arm)
        }

        var muzzleZ = -len - 0.05

        switch index {
        case 0:   // Assault Rifle
            box(0.065, 0.10, 0.34, 0, 0, -0.17, steel, metal: true)               // receiver
            box(0.058, 0.075, 0.22, 0, 0.004, -0.44, dark)                        // handguard
            box(0.062, 0.016, 0.2, 0, 0.056, -0.2, accent)                        // top stripe
            cyl(0.011, 0.07, 0, 0.012, -0.55, light)                              // barrel tip
            cyl(0.015, 0.04, 0, 0.012, -0.585, dark)                              // flash hider
            box(0.05, 0.085, 0.16, 0, -0.01, 0.08, dark)                          // stock
            box(0.045, 0.10, 0.05, 0, -0.095, -0.06, dark, tilt: -0.25)           // grip
            box(0.04, 0.13, 0.06, 0, -0.115, -0.22, steel, metal: true, tilt: 0.12)   // magazine
            box(0.03, 0.022, 0.03, 0, 0.07, -0.08, dark)                          // rear sight
            box(0.012, 0.04, 0.012, 0, 0.07, -0.5, dark)                          // front sight
            hand(0, -0.105, -0.06, side: 1)
            hand(0, -0.06, -0.4, side: -1)
            muzzleZ = -0.62
        case 1:   // Shotgun
            box(0.065, 0.09, 0.26, 0, 0, -0.13, steel, metal: true)               // receiver
            cyl(0.022, 0.5, 0, 0.03, -0.37, light)                                // barrel
            cyl(0.016, 0.38, 0, -0.018, -0.33, steel)                             // magazine tube
            box(0.075, 0.055, 0.17, 0, -0.035, -0.38, wood)                       // pump
            box(0.05, 0.09, 0.22, 0, -0.015, 0.11, wood)                          // stock
            box(0.014, 0.012, 0.45, 0, 0.056, -0.36, dark)                        // rib
            ball(0.008, 0, 0.062, -0.6, accent)                                   // front bead
            box(0.045, 0.10, 0.05, 0, -0.09, -0.0, wood, tilt: -0.25)             // grip
            hand(0, -0.095, 0, side: 1)
            hand(0, -0.075, -0.38, side: -1)
            muzzleZ = -0.66
        case 2:   // Sniper
            box(0.05, 0.08, 0.3, 0, 0, -0.15, steel, metal: true)                 // receiver
            cyl(0.012, 0.62, 0, 0.006, -0.6, light)                               // barrel
            cyl(0.018, 0.1, 0, 0.006, -0.9, dark)                                 // muzzle brake
            cyl(0.03, 0.26, 0, 0.088, -0.26, dark)                                // scope tube
            cyl(0.04, 0.05, 0, 0.088, -0.4, dark)                                 // scope front
            cyl(0.036, 0.04, 0, 0.088, -0.12, dark)                               // scope rear
            box(0.02, 0.03, 0.03, 0, 0.058, -0.2, steel)                          // scope mounts
            box(0.02, 0.03, 0.03, 0, 0.058, -0.32, steel)
            box(0.045, 0.09, 0.26, 0, -0.01, 0.13, accent)                        // stock
            box(0.045, 0.10, 0.05, 0, -0.095, -0.04, dark, tilt: -0.25)           // grip
            box(0.035, 0.07, 0.06, 0, -0.075, -0.18, dark)                        // magazine
            ball(0.015, 0.04, 0.02, -0.1, light)                                  // bolt handle
            hand(0, -0.1, -0.04, side: 1)
            hand(0, -0.055, -0.4, side: -1)
            muzzleZ = -0.98
        case 3:   // Handgun
            box(0.05, 0.055, 0.28, 0, 0.03, -0.15, steel, metal: true)            // slide
            box(0.045, 0.035, 0.22, 0, -0.012, -0.13, dark)                       // frame
            box(0.045, 0.11, 0.06, 0, -0.075, -0.035, dark, tilt: -0.2)           // grip
            box(0.02, 0.012, 0.06, 0, -0.04, -0.12, dark)                         // trigger guard
            box(0.052, 0.01, 0.2, 0, 0.057, -0.15, accent)                        // slide stripe
            box(0.012, 0.016, 0.012, 0, 0.065, -0.28, dark)                       // front sight
            box(0.028, 0.014, 0.014, 0, 0.065, -0.03, dark)                       // rear sight
            hand(0, -0.085, -0.03, side: 1)
            hand(-0.03, -0.1, -0.03, side: -1)
            muzzleZ = -0.34
        case 4:   // Revolver
            box(0.045, 0.075, 0.2, 0, 0, -0.1, steel, metal: true)                // frame
            box(0.03, 0.035, 0.2, 0, 0.016, -0.26, light, metal: true)            // barrel
            cyl(0.04, 0.075, 0, 0.002, -0.12, accent)                             // drum
            box(0.045, 0.11, 0.06, 0, -0.085, 0, wood, tilt: -0.28)               // grip
            box(0.012, 0.03, 0.02, 0, 0.052, -0.01, dark)                         // hammer
            box(0.01, 0.02, 0.01, 0, 0.048, -0.35, dark)                          // front sight
            hand(0, -0.09, 0, side: 1)
            hand(-0.03, -0.105, 0, side: -1)
            muzzleZ = -0.4
        case 5:   // Knife
            box(0.032, 0.036, 0.12, 0, -0.02, 0, dark)                            // handle
            box(0.05, 0.012, 0.02, 0, -0.02, -0.07, light, metal: true)           // guard
            box(0.012, 0.055, 0.24, 0, -0.012, -0.2, light, metal: true)          // blade
            hand(0, -0.03, 0.01, side: 1)
        case 6:  // Katana
            box(0.032, 0.032, 0.2, 0, -0.02, 0, dark)                             // handle
            cyl(0.045, 0.01, 0, -0.02, -0.11, accent)                             // guard
            box(0.008, 0.045, 0.52, 0, -0.012, -0.38, light, metal: true)         // blade
            box(0.01, 0.01, 0.52, 0, 0.012, -0.38, accent)                        // spine highlight
            hand(0, -0.03, 0.04, side: 1)
        case 7:   // SMG
            box(0.06, 0.09, 0.26, 0, 0, -0.13, steel, metal: true)
            box(0.052, 0.07, 0.12, 0, 0.004, -0.32, dark)
            box(0.056, 0.014, 0.18, 0, 0.05, -0.14, accent)
            cyl(0.012, 0.06, 0, 0.01, -0.39, light)
            box(0.04, 0.16, 0.05, 0, -0.12, -0.16, steel, metal: true)
            box(0.045, 0.10, 0.05, 0, -0.09, -0.02, dark, tilt: -0.25)
            box(0.04, 0.07, 0.12, 0, -0.005, 0.1, dark)
            box(0.012, 0.03, 0.012, 0, 0.065, -0.34, dark)
            hand(0, -0.1, -0.02, side: 1)
            hand(0, -0.07, -0.3, side: -1)
            muzzleZ = -0.44
        case 8:   // Marksman
            box(0.055, 0.085, 0.34, 0, 0, -0.17, steel, metal: true)
            cyl(0.012, 0.5, 0, 0.01, -0.55, light)
            box(0.05, 0.07, 0.2, 0, -0.005, -0.42, wood)
            cyl(0.022, 0.2, 0, 0.075, -0.2, dark)
            box(0.02, 0.025, 0.03, 0, 0.055, -0.15, steel)
            box(0.05, 0.09, 0.22, 0, -0.01, 0.12, wood)
            box(0.045, 0.10, 0.05, 0, -0.095, -0.04, dark, tilt: -0.25)
            box(0.035, 0.1, 0.05, 0, -0.095, -0.2, steel, metal: true)
            hand(0, -0.1, -0.04, side: 1)
            hand(0, -0.055, -0.4, side: -1)
            muzzleZ = -0.82
        case 9:   // LMG
            box(0.07, 0.11, 0.4, 0, 0, -0.2, steel, metal: true)
            cyl(0.014, 0.4, 0, 0.012, -0.6, light)
            box(0.06, 0.08, 0.18, 0, 0.004, -0.5, dark)
            box(0.1, 0.1, 0.12, 0, -0.1, -0.2, accent)               // ammo box
            box(0.012, 0.05, 0.012, 0, 0.09, -0.75, dark)            // bipod hint
            box(0.062, 0.016, 0.3, 0, 0.062, -0.2, dark)
            box(0.05, 0.09, 0.2, 0, -0.01, 0.12, dark)
            box(0.045, 0.10, 0.05, 0, -0.1, -0.02, dark, tilt: -0.25)
            hand(0, -0.105, -0.02, side: 1)
            hand(0, -0.06, -0.5, side: -1)
            muzzleZ = -0.8
        case 10:  // Machine Pistol
            box(0.05, 0.06, 0.24, 0, 0.03, -0.13, steel, metal: true)
            box(0.045, 0.04, 0.18, 0, -0.012, -0.11, dark)
            box(0.045, 0.11, 0.06, 0, -0.075, -0.03, dark, tilt: -0.2)
            box(0.035, 0.14, 0.04, 0, -0.1, -0.15, steel, metal: true)
            box(0.052, 0.01, 0.16, 0, 0.06, -0.13, accent)
            hand(0, -0.085, -0.03, side: 1)
            hand(-0.03, -0.1, -0.03, side: -1)
            muzzleZ = -0.3
        case 11:  // Double Barrel
            cyl(0.02, 0.34, -0.022, 0.02, -0.22, light)
            cyl(0.02, 0.34, 0.022, 0.02, -0.22, light)
            box(0.07, 0.08, 0.14, 0, 0, -0.04, steel, metal: true)
            box(0.07, 0.04, 0.14, 0, -0.03, -0.25, wood)
            box(0.045, 0.09, 0.2, 0, -0.015, 0.14, wood)
            box(0.045, 0.1, 0.05, 0, -0.09, 0, wood, tilt: -0.25)
            ball(0.008, 0, 0.05, -0.39, accent)
            hand(0, -0.095, 0, side: 1)
            hand(0, -0.07, -0.25, side: -1)
            muzzleZ = -0.44
        case 12:  // Axe
            box(0.03, 0.03, 0.5, 0, -0.02, -0.1, wood)               // handle
            box(0.025, 0.14, 0.1, 0, 0.0, -0.38, light, metal: true) // head
            box(0.02, 0.2, 0.04, 0, 0.0, -0.33, steel, metal: true)  // blade edge
            box(0.02, 0.04, 0.03, 0, 0.0, -0.4, accent)
            hand(0, -0.03, 0.05, side: 1)
        default:  // Spear
            box(0.024, 0.024, 0.9, 0, -0.02, -0.3, wood)             // shaft
            box(0.016, 0.05, 0.2, 0, -0.02, -0.85, light, metal: true) // tip
            box(0.04, 0.012, 0.03, 0, -0.02, -0.74, accent)
            hand(0, -0.03, 0.05, side: 1)
            hand(0, -0.03, -0.25, side: -1)
        }

        // Muzzle flash: a bright core with four spikes (hidden until you fire)
        flash.childNodes.forEach { $0.removeFromParentNode() }
        flash.geometry = nil
        let flashMat = SCNMaterial()
        flashMat.lightingModel = .constant
        flashMat.diffuse.contents = NSColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        let core = SCNNode(geometry: SCNSphere(radius: 0.03))
        core.geometry?.materials = [flashMat]
        flash.addChildNode(core)
        for i in 0..<4 {
            let spike = SCNNode(geometry: SCNBox(width: 0.2, height: 0.012, length: 0.012, chamferRadius: 0))
            spike.geometry?.materials = [flashMat]
            spike.eulerAngles.z = CGFloat(i) * CGFloat.pi / 4
            flash.addChildNode(spike)
        }
        flash.position = SCNVector3(0, 0.01, muzzleZ)
        flash.isHidden = true
        gun.addChildNode(flash)
    }
}
