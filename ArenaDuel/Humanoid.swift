//
//  Humanoid.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 23/11/2026.
//

import SceneKit
import AppKit

/// A simple blocky player model: body, head, swinging legs and arms, and a gun.
/// The root origin is the body centre (0.9 above the floor when standing).
/// Every part is named with `tag` (for example "p3"), and the head is "p3_head", so shots can tell who was hit.
final class Humanoid {
    let tag: String
    let root = SCNNode()
    let head = SCNNode()
    let legL = SCNNode()
    let legR = SCNNode()
    let armL = SCNNode()
    let armR = SCNNode()
    let muzzle = SCNNode()
    private(set) var materials: [SCNMaterial] = []
    private var teamMaterials: [SCNMaterial] = []

    init(color: NSColor, tag: String) {
        self.tag = tag
        root.name = tag
        let skin = NSColor(red: 0.95, green: 0.78, blue: 0.62, alpha: 1)
        let dark = NSColor(white: 0.18, alpha: 1)

        // Torso
        root.addChildNode(box(0.5, 0.7, 0.3, color, at: SCNVector3(0, 0.2, 0), team: true))

        // Head (named separately so headshots can be detected)
        let headGeo = SCNSphere(radius: 0.18)
        headGeo.materials = [material(skin)]
        head.geometry = headGeo
        head.name = tag + "_head"
        head.position = SCNVector3(0, 0.82, 0)
        root.addChildNode(head)

        // Legs swing from the hip
        for (pivot, x) in [(legL, CGFloat(-0.13)), (legR, CGFloat(0.13))] {
            pivot.position = SCNVector3(x, -0.15, 0)
            pivot.addChildNode(box(0.2, 0.75, 0.22, dark, at: SCNVector3(0, -0.375, 0)))
            root.addChildNode(pivot)
        }

        // Arms swing from the shoulder
        for (pivot, x) in [(armL, CGFloat(-0.35)), (armR, CGFloat(0.35))] {
            pivot.position = SCNVector3(x, 0.5, 0)
            pivot.addChildNode(box(0.15, 0.6, 0.15, color, at: SCNVector3(0, -0.3, 0), team: true))
            root.addChildNode(pivot)
        }
        armR.eulerAngles.x = 1.25      // right arm held out forward

        // Gun
        root.addChildNode(box(0.07, 0.1, 0.5, dark, at: SCNVector3(0.35, 0.3, -0.5)))

        // Muzzle flash (hidden until this player fires)
        let flashGeo = SCNSphere(radius: 0.09)
        let flashMat = SCNMaterial()
        flashMat.diffuse.contents = NSColor.yellow
        flashMat.emission.contents = NSColor.orange
        flashGeo.materials = [flashMat]
        muzzle.geometry = flashGeo
        muzzle.position = SCNVector3(0.35, 0.3, -0.8)
        muzzle.isHidden = true
        root.addChildNode(muzzle)
    }

    private func material(_ color: NSColor, team: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        materials.append(m)
        if team { teamMaterials.append(m) }
        return m
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ color: NSColor, at p: SCNVector3, team: Bool = false) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: 0.02)
        g.materials = [material(color, team: team)]
        let n = SCNNode(geometry: g)
        n.name = tag
        n.position = p
        return n
    }

    /// Recolour the body (blue for teammates, red for enemies).
    func setColor(_ color: NSColor) {
        teamMaterials.forEach { $0.diffuse.contents = color }
    }

    /// Swing the limbs. `phase` keeps increasing while moving; `speed` is units per second.
    func animate(speed: Float, phase: Float) {
        let amp = CGFloat(min(1, speed / 4) * 0.7)
        let s = CGFloat(sin(phase))
        legL.eulerAngles.x = s * amp
        legR.eulerAngles.x = -s * amp
        armL.eulerAngles.x = -s * amp * 0.8
    }

    func flash() {
        for m in materials { m.emission.contents = NSColor.white }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.materials.forEach { $0.emission.contents = NSColor.black }
        }
    }

    func fireFlash() {
        muzzle.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.muzzle.isHidden = true
        }
    }
}
