//
//  Weapon.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 23/11/2026.
//

import Foundation
import CoreGraphics

/// All the numbers that make each gun feel different.
struct Weapon {
    let name: String
    let slot: Int              // 0 = primary, 1 = secondary, 2 = melee
    let damage: Int            // per bullet (a shotgun fires several)
    let headMul: Float         // headshot damage multiplier
    let pellets: Int           // bullets per shot
    let fireDelay: Double      // seconds between shots
    let magSize: Int           // 0 = melee weapon, no ammo
    let reloadTime: Double
    let auto: Bool             // hold the mouse to keep firing
    let sound: String
    let range: Float           // how far a bullet travels
    let falloffStart: Float    // damage starts dropping after this distance
    let falloffEnd: Float      // ...and reaches its minimum here
    let minDamageMul: Float
    let spreadHip: Float       // bullet cone in degrees when firing from the hip, standing still
    let spreadAds: Float       // ...and when aiming down sights
    let moveSpread: Float      // extra spread while moving at full speed
    let airSpread: Float       // extra spread while in the air
    let bloomPerShot: Float    // spread added by each shot
    let maxBloom: Float
    let bloomRecover: Float    // degrees of bloom recovered per second
    let kickUp: Float          // vertical recoil per shot (radians)
    let kickSide: Float        // horizontal recoil per shot (radians)
    let adsFov: Float          // field-of-view multiplier when aiming (smaller = more zoom)
    let scope: Bool            // shows a scope overlay when aiming
    let moveMul: Float         // movement speed while holding this weapon
    let equipTime: Double      // delay before you can fire after switching
    let sightY: CGFloat        // height of the sights above the model centre (for aiming down sights)
    let gunLength: CGFloat     // size of the first-person model

    var melee: Bool { magSize == 0 }

    static let slotNames = ["Primary", "Secondary", "Melee"]

    // Ratings (0...1) shown as bars in the loadout menu
    var power: Double { min(1, Double(damage * pellets) / 100) }
    var rate: Double { melee ? min(1, 1 / fireDelay / 4) : min(1, 1 / fireDelay / 12) }
    var reach: Double { min(1, Double(range) / 150) }
    var accuracy: Double { max(0.05, 1 - Double(spreadHip) / 6) }

    static let all: [Weapon] = [
        // 0
        Weapon(name: "Assault Rifle", slot: 0, damage: 11, headMul: 1.5, pellets: 1, fireDelay: 0.085,
               magSize: 30, reloadTime: 2.0, auto: true, sound: "Pop",
               range: 130, falloffStart: 35, falloffEnd: 90, minDamageMul: 0.6,
               spreadHip: 0.9, spreadAds: 0.1, moveSpread: 1.5, airSpread: 2.5,
               bloomPerShot: 0.2, maxBloom: 2.0, bloomRecover: 8,
               kickUp: 0.011, kickSide: 0.005, adsFov: 0.78, scope: false,
               moveMul: 0.95, equipTime: 0.4, sightY: 0.078, gunLength: 0.55),
        // 1
        Weapon(name: "Shotgun", slot: 0, damage: 11, headMul: 1.3, pellets: 8, fireDelay: 0.9,
               magSize: 6, reloadTime: 2.6, auto: false, sound: "Blow",
               range: 50, falloffStart: 8, falloffEnd: 28, minDamageMul: 0.12,
               spreadHip: 4.5, spreadAds: 3.2, moveSpread: 1.0, airSpread: 1.5,
               bloomPerShot: 0, maxBloom: 0, bloomRecover: 1,
               kickUp: 0.07, kickSide: 0.01, adsFov: 0.88, scope: false,
               moveMul: 0.92, equipTime: 0.5, sightY: 0.075, gunLength: 0.6),
        // 2
        Weapon(name: "Sniper", slot: 0, damage: 70, headMul: 2.0, pellets: 1, fireDelay: 1.25,
               magSize: 5, reloadTime: 2.8, auto: false, sound: "Sosumi",
               range: 400, falloffStart: 9999, falloffEnd: 10000, minDamageMul: 1.0,
               spreadHip: 0.7, spreadAds: 0.0, moveSpread: 1.2, airSpread: 2.2,
               bloomPerShot: 0, maxBloom: 0, bloomRecover: 1,
               kickUp: 0.06, kickSide: 0.008, adsFov: 0.2, scope: true,
               moveMul: 0.85, equipTime: 0.7, sightY: 0.07, gunLength: 0.9),
        // 3
        Weapon(name: "Handgun", slot: 1, damage: 24, headMul: 1.75, pellets: 1, fireDelay: 0.20,
               magSize: 14, reloadTime: 1.3, auto: false, sound: "Pop",
               range: 90, falloffStart: 20, falloffEnd: 55, minDamageMul: 0.6,
               spreadHip: 0.6, spreadAds: 0.05, moveSpread: 1.0, airSpread: 2.0,
               bloomPerShot: 0.5, maxBloom: 1.8, bloomRecover: 9,
               kickUp: 0.022, kickSide: 0.006, adsFov: 0.85, scope: false,
               moveMul: 1.0, equipTime: 0.25, sightY: 0.065, gunLength: 0.32),
        // 4
        Weapon(name: "Revolver", slot: 1, damage: 26, headMul: 1.6, pellets: 1, fireDelay: 0.55,
               magSize: 6, reloadTime: 2.2, auto: false, sound: "Pop",
               range: 110, falloffStart: 30, falloffEnd: 75, minDamageMul: 0.8,
               spreadHip: 0.6, spreadAds: 0.03, moveSpread: 1.0, airSpread: 2.0,
               bloomPerShot: 0.6, maxBloom: 1.4, bloomRecover: 6,
               kickUp: 0.05, kickSide: 0.01, adsFov: 0.82, scope: false,
               moveMul: 1.0, equipTime: 0.35, sightY: 0.06, gunLength: 0.36),
        // 5
        Weapon(name: "Knife", slot: 2, damage: 40, headMul: 1.0, pellets: 1, fireDelay: 0.4,
               magSize: 0, reloadTime: 0, auto: false, sound: "Purr",
               range: 3.4, falloffStart: 99, falloffEnd: 100, minDamageMul: 1.0,
               spreadHip: 0, spreadAds: 0, moveSpread: 0, airSpread: 0,
               bloomPerShot: 0, maxBloom: 0, bloomRecover: 1,
               kickUp: 0.02, kickSide: 0.0, adsFov: 1.0, scope: false,
               moveMul: 1.15, equipTime: 0.25, sightY: 0, gunLength: 0.3),
        // 6
        Weapon(name: "Katana", slot: 2, damage: 55, headMul: 1.0, pellets: 1, fireDelay: 0.75,
               magSize: 0, reloadTime: 0, auto: false, sound: "Purr",
               range: 4.0, falloffStart: 99, falloffEnd: 100, minDamageMul: 1.0,
               spreadHip: 0, spreadAds: 0, moveSpread: 0, airSpread: 0,
               bloomPerShot: 0, maxBloom: 0, bloomRecover: 1,
               kickUp: 0.03, kickSide: 0.0, adsFov: 1.0, scope: false,
               moveMul: 1.1, equipTime: 0.3, sightY: 0, gunLength: 0.5),
        // 7
        Weapon(name: "SMG", slot: 0, damage: 8, headMul: 1.4, pellets: 1, fireDelay: 0.06,
               magSize: 35, reloadTime: 1.7, auto: true, sound: "Bottle",
               range: 80, falloffStart: 15, falloffEnd: 45, minDamageMul: 0.5,
               spreadHip: 1.4, spreadAds: 0.4, moveSpread: 1.2, airSpread: 2.0,
               bloomPerShot: 0.25, maxBloom: 3.0, bloomRecover: 8,
               kickUp: 0.008, kickSide: 0.006, adsFov: 0.85, scope: false,
               moveMul: 1.05, equipTime: 0.3, sightY: 0.07, gunLength: 0.42),
        // 8
        Weapon(name: "Marksman", slot: 0, damage: 40, headMul: 1.75, pellets: 1, fireDelay: 0.38,
               magSize: 10, reloadTime: 2.3, auto: false, sound: "Funk",
               range: 220, falloffStart: 60, falloffEnd: 150, minDamageMul: 0.8,
               spreadHip: 2.2, spreadAds: 0.02, moveSpread: 1.8, airSpread: 3.0,
               bloomPerShot: 0.5, maxBloom: 1.5, bloomRecover: 5,
               kickUp: 0.035, kickSide: 0.006, adsFov: 0.5, scope: false,
               moveMul: 0.9, equipTime: 0.5, sightY: 0.078, gunLength: 0.7),
        // 9
        Weapon(name: "LMG", slot: 0, damage: 10, headMul: 1.3, pellets: 1, fireDelay: 0.075,
               magSize: 80, reloadTime: 4.2, auto: true, sound: "Pop",
               range: 120, falloffStart: 30, falloffEnd: 85, minDamageMul: 0.6,
               spreadHip: 1.6, spreadAds: 0.3, moveSpread: 2.0, airSpread: 3.0,
               bloomPerShot: 0.15, maxBloom: 3.5, bloomRecover: 5,
               kickUp: 0.009, kickSide: 0.007, adsFov: 0.85, scope: false,
               moveMul: 0.8, equipTime: 0.7, sightY: 0.08, gunLength: 0.62),
        // 10
        Weapon(name: "Machine Pistol", slot: 1, damage: 7, headMul: 1.4, pellets: 1, fireDelay: 0.055,
               magSize: 24, reloadTime: 1.5, auto: true, sound: "Bottle",
               range: 60, falloffStart: 10, falloffEnd: 35, minDamageMul: 0.45,
               spreadHip: 1.6, spreadAds: 0.5, moveSpread: 1.0, airSpread: 2.0,
               bloomPerShot: 0.3, maxBloom: 3.2, bloomRecover: 7,
               kickUp: 0.01, kickSide: 0.008, adsFov: 0.9, scope: false,
               moveMul: 1.0, equipTime: 0.2, sightY: 0.06, gunLength: 0.3),
        // 11
        Weapon(name: "Double Barrel", slot: 1, damage: 10, headMul: 1.3, pellets: 8, fireDelay: 0.35,
               magSize: 2, reloadTime: 2.0, auto: false, sound: "Blow",
               range: 40, falloffStart: 6, falloffEnd: 22, minDamageMul: 0.1,
               spreadHip: 4.0, spreadAds: 3.0, moveSpread: 1.0, airSpread: 1.5,
               bloomPerShot: 0, maxBloom: 0, bloomRecover: 1,
               kickUp: 0.06, kickSide: 0.012, adsFov: 0.9, scope: false,
               moveMul: 1.0, equipTime: 0.35, sightY: 0.06, gunLength: 0.4),
        // 12
        Weapon(name: "Axe", slot: 2, damage: 60, headMul: 1.0, pellets: 1, fireDelay: 0.8,
               magSize: 0, reloadTime: 0, auto: false, sound: "Frog",
               range: 3.6, falloffStart: 99, falloffEnd: 100, minDamageMul: 1.0,
               spreadHip: 0, spreadAds: 0, moveSpread: 0, airSpread: 0,
               bloomPerShot: 0, maxBloom: 0, bloomRecover: 1,
               kickUp: 0.03, kickSide: 0.0, adsFov: 1.0, scope: false,
               moveMul: 1.05, equipTime: 0.4, sightY: 0, gunLength: 0.45),
        // 13
        Weapon(name: "Spear", slot: 2, damage: 42, headMul: 1.0, pellets: 1, fireDelay: 0.6,
               magSize: 0, reloadTime: 0, auto: false, sound: "Purr",
               range: 5.0, falloffStart: 99, falloffEnd: 100, minDamageMul: 1.0,
               spreadHip: 0, spreadAds: 0, moveSpread: 0, airSpread: 0,
               bloomPerShot: 0, maxBloom: 0, bloomRecover: 1,
               kickUp: 0.025, kickSide: 0.0, adsFov: 1.0, scope: false,
               moveMul: 1.05, equipTime: 0.35, sightY: 0, gunLength: 0.9),
    ]
}
