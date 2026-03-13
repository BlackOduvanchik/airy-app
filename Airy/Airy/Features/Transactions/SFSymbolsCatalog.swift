//
//  SFSymbolsCatalog.swift
//  Airy
//
//  Curated SF Symbol names by category for category icons. Single source of truth for Icon Library and quick pick.
//

import Foundation

enum SFSymbolsCatalog {
    static let finance: [String] = [
        "creditcard.fill", "creditcard", "dollarsign", "dollarsign.circle.fill", "dollarsign.square.fill",
        "centsign", "yensign.circle.fill", "eurosign.circle.fill", "banknote.fill", "banknote",
        "chart.line.uptrend.xyaxis", "chart.bar.fill", "chart.pie.fill", "chart.xyaxis.line",
        "briefcase.fill", "briefcase", "shield.fill", "shield", "doc.text.fill", "doc.richtext.fill",
        "tray.full.fill", "archivebox.fill", "building.columns.fill", "building.2.fill",
        "percent", "number", "sum", "equal.circle.fill", "dollarsign.circle",
        "creditcard.and.123", "chart.bar.doc.horizontal.fill",
    ]

    static let food: [String] = [
        "cart.fill", "cart", "bag.fill", "bag", "basket.fill", "basket",
        "fork.knife", "fork.knife.circle.fill", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill",
        "birthday.cake.fill", "leaf.fill", "leaf", "carrot.fill", "apple.logo",
        "wineglass.fill", "mug.fill",
        "fish.fill", "birthday.cake", "frying.pan.fill", "refrigerator.fill",
        "cup.and.saucer", "mug", "wineglass", "carrot", "leaf.circle.fill",
    ]

    static let transport: [String] = [
        "car.fill", "car", "bus.fill", "bus", "tram.fill", "tram",
        "bicycle", "airplane", "airplane.departure", "airplane.arrival",
        "ferry.fill", "fuelpump.fill", "fuelpump", "location.fill", "location",
        "map.fill", "map", "mappin.circle.fill", "mappin.and.ellipse",
        "figure.walk", "figure.run", "figure.roll", "scooter",
        "parkingsign", "road.lanes", "signpost.right.fill", "car.side",
    ]

    static let lifestyle: [String] = [
        "heart.fill", "heart", "star.fill", "star", "flag.fill", "flag",
        "book.fill", "book", "gamecontroller.fill", "gamecontroller",
        "sportscourt.fill", "figure.walk", "gift.fill", "gift",
        "theatermasks.fill", "paintbrush.fill", "paintbrush", "paintpalette.fill",
        "camera.fill", "camera", "photo.fill", "photo", "film.fill", "film",
        "music.note", "music.quarternote.3", "guitars.fill", "piano.keys.inverse",
        "face.smiling.fill", "sparkles", "wand.and.stars", "party.popper.fill",
    ]

    static let home: [String] = [
        "house.fill", "house", "building.2.fill", "building.2", "key.fill", "key",
        "lightbulb.fill", "lightbulb", "fan.fill", "fan", "thermometer.medium",
        "sofa.fill", "bed.double.fill", "washer.fill", "dryer.fill",
        "refrigerator.fill", "oven.fill", "microwave.fill", "dishwasher.fill",
        "lock.fill", "lock.open.fill", "door.garage.closed", "door.garage.open",
        "figure.stand", "armchair.fill", "lamp.floor.fill", "powerplug.fill",
    ]

    static let tech: [String] = [
        "iphone", "iphone.gen3", "laptopcomputer", "desktopcomputer", "tv.fill", "tv",
        "phone.fill", "phone", "envelope.fill", "envelope", "message.fill", "message",
        "wifi", "wifi.circle.fill", "antenna.radiowaves.left.and.right", "bolt.fill", "bolt",
        "gearshape.fill", "gearshape", "square.grid.2x2.fill", "square.grid.2x2",
        "cpu.fill", "cpu", "tag.fill", "tag", "barcode", "qrcode",
        "printer.fill", "scanner.fill", "externaldrive.fill", "internaldrive.fill",
        "display", "macpro.gen3", "airport.extreme.tower", "hifispeaker.fill",
    ]

    static let health: [String] = [
        "heart.fill", "heart.text.square.fill", "cross.case.fill", "cross.vial.fill",
        "pills.fill", "pills", "staroflife.fill", "stethoscope",
        "figure.run", "figure.yoga", "dumbbell.fill", "sportscourt.fill",
        "brain.head.profile", "heart.circle.fill", "waveform.path.ecg",
        "bed.double.fill", "thermometer.medium", "bandage.fill",
    ]

    static let shopping: [String] = [
        "bag.fill", "bag", "cart.fill", "cart", "basket.fill", "creditcard.fill",
        "giftcard.fill", "tag.fill", "tag", "percent", "dollarsign.circle.fill",
        "storefront.fill", "storefront", "building.2.fill", "mappin.circle.fill",
        "handbag.fill", "tshirt.fill", "crown.fill", "sparkles",
    ]

    static let work: [String] = [
        "briefcase.fill", "briefcase", "building.2.fill", "building.2",
        "desktopcomputer", "laptopcomputer", "printer.fill", "doc.fill", "doc.text.fill",
        "folder.fill", "folder", "paperclip", "link", "calendar",
        "clock.fill", "clock", "alarm.fill", "timer", "checkmark.circle.fill",
        "person.fill", "person.2.fill", "person.3.fill", "building.columns.fill",
    ]

    static let nature: [String] = [
        "leaf.fill", "leaf", "tree.fill", "tree", "flower.fill", "camera.macro",
        "sun.max.fill", "moon.fill", "cloud.fill", "cloud.rain.fill",
        "drop.fill", "drop", "flame.fill", "flame", "snowflake",
        "bird.fill", "fish.fill", "pawprint.fill", "ant.fill",
        "ladybug.fill", "tortoise.fill", "hare.fill", "lizard.fill",
    ]

    static let education: [String] = [
        "book.fill", "book", "book.closed.fill", "graduationcap.fill",
        "pencil", "pencil.circle.fill", "highlighter", "paintbrush.fill",
        "ruler.fill", "scissors", "paperclip", "doc.fill",
        "lightbulb.fill", "brain.head.profile", "person.crop.circle.badge.questionmark",
    ]

    static let byCategory: [String: [String]] = [
        "Finance": finance,
        "Food": food,
        "Transport": transport,
        "Lifestyle": lifestyle,
        "Home": home,
        "Tech": tech,
        "Health": health,
        "Shopping": shopping,
        "Work": work,
        "Nature": nature,
        "Education": education,
    ]

    static let categoryOrder: [String] = [
        "Finance", "Food", "Transport", "Lifestyle", "Home", "Tech",
        "Health", "Shopping", "Work", "Nature", "Education",
    ]

    static var allSymbols: [String] {
        categoryOrder.flatMap { byCategory[$0] ?? [] }
    }
}
