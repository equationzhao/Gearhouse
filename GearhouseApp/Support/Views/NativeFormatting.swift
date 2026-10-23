import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

let nativeTypes = [("Bike","自行车"),("Shoes","跑鞋"),("CyclingShoes","锁鞋"),("Cleats","锁片"),("Pedals","锁踏"),("PowerMeter","功率计"),("Handlebar","车把"),("Saddle","坐垫"),("Seatpost","坐杆"),("Chainrings","牙盘"),("Crankset","曲柄"),("Spider","盘爪"),("Wheelset","轮组"),("Tyre","轮胎"),("Tube","内胎"),("BrakePads","来令片"),("BrakeRotor","碟片"),("Cassette","飞轮"),("Chain","链条"),("FrontDerailleur","前变速器"),("RearDerailleur","后变速器"),("Trainer","骑行台"),("Equipment","其他装备")]
let nativeEventKinds = [("maintenance","保养"),("crash","摔车"),("dripWax","滴蜡"),("hotWax","煮蜡"),("cleaning","清洁"),("inspection","检查"),("custom","其他")]
func nativeType(_ type: String) -> String { nativeTypes.first { $0.0 == type }?.1 ?? type }
func nativeDistance(_ value: Value) -> String { value.isNull ? "—" : String(format: "%.1f km", value.double / 1000) }
func nativeDuration(_ value: Value) -> String { value.isNull ? "—" : "\(value.integer / 3600)h \((value.integer % 3600) / 60)m" }
func nativeIcon(_ type: String) -> String { type == "Bike" ? "bicycle" : type.contains("Shoes") ? "shoe" : type == "Chain" ? "link" : "gearshape" }
