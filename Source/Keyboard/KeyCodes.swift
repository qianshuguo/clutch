import Foundation

// Virtual key codes shared by the event tap, the state machine, and the views.
// Caps Lock is remapped to F18 by hidutil, so a physical Caps press arrives as `hyper`.
// Foundation-only, so the pure keyboard tests can compile it.
enum KeyCode {
    static let s: UInt16 = 1
    static let w: UInt16 = 13
    static let returnKey: UInt16 = 36
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let keypadEnter: UInt16 = 76
    static let hyper: UInt16 = 79 // F18
    // Arrows, Home, End, Page Up, Page Down.
    static let navigation: [UInt16] = [123, 124, 125, 126, 115, 119, 116, 121]

    static func isReturn(_ code: UInt16) -> Bool { code == returnKey || code == keypadEnter }
}

let keys: [(String, UInt16)] = [
    ("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),
    ("H",4),("I",34),("J",38),("K",40),("L",37),("M",46),("N",45),
    ("O",31),("P",35),("Q",12),("R",15),("S",1),("T",17),("U",32),
    ("V",9),("W",13),("X",7),("Y",16),("Z",6),
    ("0",29),("1",18),("2",19),("3",20),("4",21),("5",23),
    ("6",22),("7",26),("8",28),("9",25)]

extension KeyCode {
    static let lettersAndDigits: [UInt16] = keys.map { $0.1 }
    // Top-row 1…9, in order; index 0 selects the first folder.
    static let digits1to9: [UInt16] = (1...9).map { digit in keys.first { $0.0 == String(digit) }!.1 }
}

let unassignedKey: UInt16 = .max
let extraKeys: [UInt16: String] = [36:"Return",48:"Tab",49:"Space",51:"⌫",117:"⌦",
    123:"←",124:"→",125:"↓",126:"↑",115:"Home",119:"End",116:"PgUp",121:"PgDn",
    27:"−",24:"=",33:"[",30:"]",42:"\\",41:";",39:"'",43:",",47:".",44:"/",50:"`",
    122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",
    109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",80:"F19",90:"F20"]
func keyName(_ code: UInt16) -> String? { keys.first { $0.1 == code }?.0 ?? extraKeys[code] }
