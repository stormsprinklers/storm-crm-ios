import Foundation

enum OfflineVisitWindow {
    static let pastDays = 3
    static let futureDays = 3

    static func range(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -pastDays, to: today) ?? today
        let endDay = calendar.date(byAdding: .day, value: futureDays, to: today) ?? today
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay) ?? endDay
        return (start, end)
    }

    static func contains(startAt: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let date = APIDateFormatting.parse(startAt) else { return false }
        let window = range(now: now, calendar: calendar)
        return date >= window.start && date <= window.end
    }
}

/// Raw JSON snapshots of full visit payloads so techs can open jobs and keep working offline.
enum OfflineVisitDetailStore {
    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("OfflineVisitDetails", isDirectory: true)
    }

    static func saveVisitJSON(_ data: Data, id: String) {
        write(data, name: "visit-\(id).json")
    }

    static func saveChecklistsJSON(_ data: Data, visitId: String) {
        write(data, name: "checklists-\(visitId).json")
    }

    static func visitJSON(id: String) -> Data? {
        read(name: "visit-\(id).json")
    }

    static func checklistsJSON(visitId: String) -> Data? {
        read(name: "checklists-\(visitId).json")
    }

    static func cachedVisitDetail(id: String) -> VisitDetailDTO? {
        guard let data = visitJSON(id: id) else { return nil }
        return try? JSONCoding.makeDecoder().decode(VisitDetailDTO.self, from: data)
    }

    static func cachedChecklists(visitId: String) -> [ChecklistDTO] {
        guard let data = checklistsJSON(visitId: visitId) else { return [] }
        return (try? JSONCoding.makeDecoder().decode([ChecklistDTO].self, from: data)) ?? []
    }

    static func patchVisitJSON(id: String, mutate: (inout [String: Any]) -> Void) {
        var object = visitObject(id: id) ?? ["id": id]
        mutate(&object)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        saveVisitJSON(data, id: id)
    }

    static func applyWorkSummary(visitId: String, summary: String?) {
        patchVisitJSON(id: visitId) { object in
            if let summary, !summary.isEmpty {
                object["workSummary"] = summary
            } else {
                object["workSummary"] = NSNull()
            }
        }
    }

    static func appendNote(visitId: String, note: [String: Any]) {
        patchVisitJSON(id: visitId) { object in
            var notes = object["notes"] as? [[String: Any]] ?? []
            notes.append(note)
            object["notes"] = notes
        }
    }

    private static func visitObject(id: String) -> [String: Any]? {
        guard let data = visitJSON(id: id),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func write(_ data: Data, name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read(name: String) -> Data? {
        let url = directory.appendingPathComponent(name)
        return try? Data(contentsOf: url)
    }
}

enum OfflineVisitPrefetch {
    static func fetch(id: String, api: APIClient) async {
        do {
            let visitData = try await api.getData(path: APIPath.visit(id))
            OfflineVisitDetailStore.saveVisitJSON(visitData, id: id)
        } catch {
            return
        }
        if let checklistData = try? await api.getData(path: APIPath.visitChecklists(id)) {
            OfflineVisitDetailStore.saveChecklistsJSON(checklistData, visitId: id)
        }
    }
}
