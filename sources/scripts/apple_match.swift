// apple_match.swift: each app place's Apple Maps place, found with MapKit (a Mac, no key).
//
//     swift sources/scripts/apple_match.swift places.json
//
// Reads [{id, entry_id, name, address, lat, lon}] and prints one JSON line per place: the Apple Maps
// place whose name carries most of ours, within 300 m of its pin (800 m when it carries all of it),
// nearest on a tie, searched by name and then by name and address, as
// {id, entry_id, name, apple_place_id, apple_name, metres}; else with `missing`.
// apple_maps.py runs it (`match`) and turns the lines into a migration; nothing here writes.
import MapKit

struct Place: Decodable { let id: String; let entry_id: String; let name: String; let address: String?; let lat: Double; let lon: Double }

let skip: Set<String> = ["the", "and", "inc", "llc", "joseph", "saint", "st.", "of", "&", "-", "|", "co", "company"]
func words(_ s: String) -> Set<String> {
    Set(s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 && !skip.contains($0) })
}

/// How much of our name Apple's name carries: the share of our words in it, a word also counting
/// when Apple joins or splits it ("Autobody" in "CMS Auto Body"). Over half is the same place;
/// "Coborn's Pharmacy" and "Coborn's Liquor" (half) are two.
func likeness(_ ours: String, _ apple: String) -> Double {
    let mine = words(ours), theirs = words(apple)
    let squashed = apple.lowercased().filter { $0.isLetter || $0.isNumber }
    guard !mine.isEmpty else { return 0 }
    return Double(mine.filter { theirs.contains($0) || squashed.contains($0) }.count) / Double(mine.count)
}

func best(_ query: String, near here: CLLocation, name: String) async -> (MKMapItem, Int)? {
    let req = MKLocalSearch.Request()
    req.naturalLanguageQuery = query
    req.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000)
    req.resultTypes = .pointOfInterest
    guard let items = try? await MKLocalSearch(request: req).start().mapItems else { return nil }
    var pick: (item: MKMapItem, metres: Int, like: Double)?
    for item in items where item.identifier != nil {
        let like = likeness(name, item.name ?? "")
        let metres = Int(item.location.distance(from: here))
        // Our pins sit up to ~500 m off Apple's (RJ's Auto Repair), so a full name may be further away.
        guard like > 0.5, metres <= (like == 1 ? 800 : 300) else { continue }
        if pick == nil || like > pick!.like || (like == pick!.like && metres < pick!.metres) {
            pick = (item, metres, like)
        }
    }
    return pick.map { ($0.item, $0.metres) }
}

let places = try JSONDecoder().decode([Place].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
Task {
    for p in places {
        let here = CLLocation(latitude: p.lat, longitude: p.lon)
        let name = p.name.components(separatedBy: " | ")[0]
        var hit = await best(name, near: here, name: name)
        if hit == nil, let address = p.address {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            hit = await best("\(name), \(address)", near: here, name: name)
        }
        var line: [String: Any] = ["id": p.id, "entry_id": p.entry_id, "name": name]
        if let (item, metres) = hit {
            line["apple_place_id"] = item.identifier!.rawValue
            line["apple_name"] = item.name ?? ""
            line["metres"] = metres
        } else {
            line["missing"] = "no Apple Maps place near its pin carries its name"
        }
        print(String(data: try! JSONSerialization.data(withJSONObject: line, options: .sortedKeys), encoding: .utf8)!)
        fflush(stdout)
        try? await Task.sleep(nanoseconds: 1_300_000_000)  // MapKit refuses bursts (MKError 3)
    }
    exit(0)
}
RunLoop.main.run()
