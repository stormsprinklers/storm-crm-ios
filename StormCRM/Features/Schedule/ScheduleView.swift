import SwiftUI

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published var jobs: [VisitDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(api: APIClient, around date: Date = Date(), offlineSync: OfflineSyncManager? = nil) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
        let rangeStart = calendar.date(byAdding: .day, value: -14, to: weekStart) ?? weekStart
        guard let rangeEndDay = calendar.date(byAdding: .day, value: 20, to: weekStart),
              let rangeEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: rangeEndDay)
        else { return }

        do {
            jobs = try await api.get(
                path: APIPath.mobileSchedule,
                query: [
                    URLQueryItem(name: "start", value: APIDateFormatting.queryString(from: rangeStart)),
                    URLQueryItem(name: "end", value: APIDateFormatting.queryString(from: rangeEnd)),
                ]
            )
            offlineSync?.cacheVisits(jobs)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func jobCount(on day: Date, assignedTo employeeId: String, calendar: Calendar = .current) -> Int {
        let target = calendar.startOfDay(for: day)
        return jobs.filter { job in
            guard matchesEmployee(job, employeeId) else { return false }
            guard let start = APIDateFormatting.parse(job.startAt) else { return false }
            return calendar.isDate(start, inSameDayAs: target)
        }.count
    }

    func matchesEmployee(_ job: VisitDTO, _ employeeId: String) -> Bool {
        employeeId.isEmpty || job.assignedUser?.id == employeeId
    }
}

@MainActor
final class VisitsListViewModel: ObservableObject {
    @Published var visits: [VisitDTO] = []
    @Published var search = ""
    @Published var isLoading = false
    @Published var error: String?

    func load(api: APIClient) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        var query: [URLQueryItem] = []
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        do {
            let response: VisitsListResponse = try await api.get(path: APIPath.visits, query: query)
            visits = response.visits
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

enum ScheduleMode: String, CaseIterable, Identifiable {
    case schedule = "Schedule"
    case visits = "Visits"
    var id: String { rawValue }
}

/// Context for the quick "add job" sheet launched by tapping an empty slot.
struct ScheduleCreateContext: Identifiable {
    let id = UUID()
    let start: Date
    let assignedUserId: String?
}

struct ScheduleWeekStrip: View {
    @Binding var selectedDate: Date
    let weekStart: Date
    let jobCount: (Date) -> Int
    var onShiftWeek: (Int) -> Void

    private var calendar: Calendar { Calendar.current }

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    onShiftWeek(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Previous week")

                Text(weekTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StormTheme.navy)
                    .frame(maxWidth: .infinity)

                Button {
                    onShiftWeek(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Next week")
            }
            .foregroundStyle(StormTheme.navy)

            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    dayButton(for: day)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var weekTitle: String {
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
        let startMonth = weekStart.formatted(.dateTime.month(.abbreviated))
        let endMonth = weekEnd.formatted(.dateTime.month(.abbreviated))
        let year = weekStart.formatted(.dateTime.year())
        if startMonth == endMonth {
            return "\(startMonth) \(weekStart.formatted(.dateTime.day()))–\(weekEnd.formatted(.dateTime.day())), \(year)"
        }
        return "\(startMonth) \(weekStart.formatted(.dateTime.day())) – \(endMonth) \(weekEnd.formatted(.dateTime.day())), \(year)"
    }

    @ViewBuilder
    private func dayButton(for day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let count = jobCount(day)

        Button {
            selectedDate = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.semibold))
                Text(day.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isSelected ? .bold : .medium))
                Circle()
                    .fill(count > 0 ? (isSelected ? Color.white.opacity(0.9) : StormTheme.sky) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : StormTheme.navy)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(StormTheme.navy)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(StormTheme.sky, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ScheduleView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var viewModel = ScheduleViewModel()
    @StateObject private var visitsModel = VisitsListViewModel()

    @State private var navigationPath = NavigationPath()

    @State private var mode: ScheduleMode = .schedule
    @State private var colorMode: ScheduleColorMode = .technician
    @State private var jobToEdit: VisitDTO?
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var employees: [ScheduleEmployeeDTO] = []
    @State private var serviceAreas: [ScheduleServiceAreaDTO] = []
    @State private var selectedEmployeeId = ""
    @State private var createContext: ScheduleCreateContext?
    @State private var jobToDelete: VisitDTO?
    @State private var isDeleting = false

    private var calendar: Calendar { Calendar.current }

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
            ?? calendar.startOfDay(for: selectedDate)
    }

    private var canEditSchedule: Bool {
        // Field may self-create/reschedule; office keeps full edit.
        env.auth.user != nil
    }

    /// Office roles can view/switch between teammates' schedules; field techs see only their own.
    private var canViewOthers: Bool {
        env.auth.user.map { UserRoles.canEditVisitOfficeFields($0.role) } ?? false
    }

    private var jobsForSelectedDay: [VisitDTO] {
        let day = calendar.startOfDay(for: selectedDate)
        return viewModel.jobs
            .filter { job in
                guard viewModel.matchesEmployee(job, selectedEmployeeId) else { return false }
                guard let start = APIDateFormatting.parse(job.startAt) else { return false }
                return calendar.isDate(start, inSameDayAs: day)
            }
            .sorted {
                let left = APIDateFormatting.parse($0.startAt) ?? .distantFuture
                let right = APIDateFormatting.parse($1.startAt) ?? .distantFuture
                return left < right
            }
    }

    private var filteredVisits: [VisitDTO] {
        visitsModel.visits.filter { viewModel.matchesEmployee($0, selectedEmployeeId) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(ScheduleMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

                if canViewOthers {
                    employeePickerBar
                }

                Divider()

                if mode == .schedule {
                    scheduleContent
                } else {
                    visitsContent
                }
            }
            .navigationTitle(mode == .schedule ? (canEditSchedule ? "Schedule" : "My Schedule") : "Visits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .schedule {
                    ToolbarItem(placement: .topBarLeading) {
                        if !calendar.isDateInToday(selectedDate) {
                            Button("Today") {
                                selectedDate = calendar.startOfDay(for: Date())
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Color by", selection: $colorMode) {
                                ForEach(ScheduleColorMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                        } label: {
                            Label("Color by \(colorMode.label)", systemImage: "paintpalette")
                        }
                    }
                }
            }
            .navigationDestination(for: VisitDTO.self) { job in
                VisitDetailView(visitId: job.id)
            }
            .navigationDestination(for: String.self) { visitId in
                VisitDetailView(visitId: visitId)
            }
            .customerHistoryDestinations()
            .customerDetailDestination()
            .refreshable { await reload() }
            .task { await loadInitial() }
            .onChange(of: env.deepLinkNavigation) { _, navigation in
                guard let navigation else { return }
                switch navigation {
                case .visit(let visitId):
                    navigationPath.append(visitId)
                case .estimate(let estimateId):
                    navigationPath.append(CustomerHistoryDestination.estimate(estimateId))
                case .customer:
                    break
                }
                env.deepLinkNavigation = nil
            }
            .onChange(of: selectedDate) { _, _ in
                Task { await viewModel.load(api: env.apiClient, around: selectedDate, offlineSync: env.offlineSync) }
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .visits && visitsModel.visits.isEmpty {
                    Task { await visitsModel.load(api: env.apiClient) }
                }
            }
            .sheet(item: $jobToEdit) { job in
                ScheduleJobEditSheet(job: job) {
                    await reload()
                }
            }
            .sheet(item: $createContext) { context in
                ScheduleJobCreateSheet(
                    start: context.start,
                    defaultAssignedUserId: context.assignedUserId,
                    employees: employees,
                    serviceAreas: serviceAreas
                ) {
                    await reload()
                }
            }
            .alert("Remove job?", isPresented: Binding(
                get: { jobToDelete != nil },
                set: { if !$0 { jobToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { jobToDelete = nil }
                Button("Remove", role: .destructive) {
                    if let job = jobToDelete { Task { await delete(job) } }
                }
            } message: {
                Text(jobToDelete.map { "This will permanently delete “\($0.title)”." } ?? "")
            }
        }
        .background(StormTheme.page.ignoresSafeArea())
    }

    // MARK: - Employee picker

    private var employeePickerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
            Menu {
                Picker("Whose schedule", selection: $selectedEmployeeId) {
                    Text("Everyone").tag("")
                    ForEach(employees) { employee in
                        Text(employee.name).tag(employee.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedEmployeeName)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(StormTheme.navy)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private var selectedEmployeeName: String {
        if selectedEmployeeId.isEmpty { return "Everyone" }
        return employees.first(where: { $0.id == selectedEmployeeId })?.name ?? "Everyone"
    }

    // MARK: - Schedule (day) content

    @ViewBuilder
    private var scheduleContent: some View {
        VStack(spacing: 0) {
            ScheduleWeekStrip(
                selectedDate: $selectedDate,
                weekStart: weekStart,
                jobCount: { viewModel.jobCount(on: $0, assignedTo: selectedEmployeeId, calendar: calendar) }
            ) { delta in
                shiftWeek(by: delta)
            }

            Divider()

            if viewModel.isLoading && viewModel.jobs.isEmpty {
                Spacer()
                ProgressView("Loading schedule…")
                Spacer()
            } else if let error = viewModel.error, viewModel.jobs.isEmpty {
                ContentUnavailableView(
                    "Could not load schedule",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ScheduleDayTimeline(
                    jobs: jobsForSelectedDay,
                    day: calendar.startOfDay(for: selectedDate),
                    colorMode: colorMode,
                    canEdit: canEditSchedule,
                    onTapSlot: { start in
                        guard canEditSchedule else { return }
                        createContext = ScheduleCreateContext(
                            start: start,
                            assignedUserId: selectedEmployeeId.isEmpty ? nil : selectedEmployeeId
                        )
                    },
                    onEdit: { job in jobToEdit = job },
                    onDelete: { job in jobToDelete = job }
                )
                if canEditSchedule {
                    Text("Tap an empty time to add a job.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Visits (list) content

    @ViewBuilder
    private var visitsContent: some View {
        Group {
            if visitsModel.isLoading && visitsModel.visits.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = visitsModel.error, visitsModel.visits.isEmpty {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if filteredVisits.isEmpty {
                ContentUnavailableView(
                    "No visits",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("No visits match the current filter.")
                )
            } else {
                List {
                    ForEach(filteredVisits) { visit in
                        NavigationLink(value: visit.id) {
                            ScheduleRow(job: visit, colorMode: colorMode)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canEditSchedule {
                                Button(role: .destructive) { jobToDelete = visit } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                Button { jobToEdit = visit } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(StormTheme.sky)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $visitsModel.search, prompt: "Search visits")
        .onSubmit(of: .search) { Task { await visitsModel.load(api: env.apiClient) } }
    }

    // MARK: - Actions

    private func loadInitial() async {
        await viewModel.load(api: env.apiClient, around: selectedDate, offlineSync: env.offlineSync)
        if serviceAreas.isEmpty {
            let filters = try? await env.apiClient.get(path: APIPath.scheduleFilters) as ScheduleFiltersResponse
            if canViewOthers {
                employees = filters?.employees ?? []
            }
            serviceAreas = filters?.serviceAreas ?? []
        }
        if let me = env.auth.user?.id, !canViewOthers {
            selectedEmployeeId = me
        }
    }

    private func reload() async {
        await viewModel.load(api: env.apiClient, around: selectedDate, offlineSync: env.offlineSync)
        if mode == .visits || !visitsModel.visits.isEmpty {
            await visitsModel.load(api: env.apiClient)
        }
    }

    private func delete(_ job: VisitDTO) async {
        isDeleting = true
        defer { isDeleting = false; jobToDelete = nil }
        do {
            try await env.apiClient.delete(path: APIPath.visit(job.id))
            await reload()
        } catch {
            viewModel.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func shiftWeek(by delta: Int) {
        guard let newWeekStart = calendar.date(byAdding: .weekOfYear, value: delta, to: weekStart),
              let weekday = calendar.dateComponents([.weekday], from: selectedDate).weekday,
              let newSelected = calendar.date(bySetting: .weekday, value: weekday, of: newWeekStart)
        else { return }
        selectedDate = calendar.startOfDay(for: newSelected)
    }
}

// MARK: - Day timeline

private struct ScheduleDayTimeline: View {
    let jobs: [VisitDTO]
    let day: Date
    var colorMode: ScheduleColorMode = .technician
    var canEdit: Bool
    var onTapSlot: (Date) -> Void
    var onEdit: (VisitDTO) -> Void
    var onDelete: (VisitDTO) -> Void

    private let startHour = 6
    private let endHour = 21
    private let hourHeight: CGFloat = 62
    private let gutter: CGFloat = 58
    private let vPadding: CGFloat = 8

    private var calendar: Calendar { Calendar.current }
    private var hourLanes: [Int] { Array(startHour..<endHour) }
    private var contentHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight + vPadding * 2 }

    var body: some View {
        ScrollView {
            GeometryReader { geo in
                let laneWidth = max(geo.size.width - gutter - 12, 60)
                ZStack(alignment: .topLeading) {
                    ForEach(hourLanes, id: \.self) { hour in
                        hourLane(hour, laneWidth: laneWidth)
                    }
                    ForEach(jobs) { job in
                        jobBlock(job, laneWidth: laneWidth)
                    }
                }
            }
            .frame(height: contentHeight)
        }
    }

    @ViewBuilder
    private func hourLane(_ hour: Int, laneWidth: CGFloat) -> some View {
        let y = vPadding + CGFloat(hour - startHour) * hourHeight
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(.separator).opacity(0.4))
                .frame(height: 0.5)

            Text(hourLabel(hour))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: gutter - 8, alignment: .trailing)
                .offset(y: -6)

            // Tappable empty slot (falls behind job blocks in the ZStack).
            Button {
                if canEdit, let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) {
                    onTapSlot(date)
                }
            } label: {
                Rectangle().fill(Color.clear)
                    .frame(width: laneWidth, height: hourHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .offset(x: gutter)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .offset(y: y)
    }

    @ViewBuilder
    private func jobBlock(_ job: VisitDTO, laneWidth: CGFloat) -> some View {
        let layout = blockLayout(for: job)
        NavigationLink(value: job) {
            ScheduleTimelineBlock(job: job, colorMode: colorMode, compact: layout.height < 52)
                .frame(width: laneWidth, height: layout.height, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .offset(x: gutter, y: layout.y)
        .contextMenu {
            if canEdit {
                Button { onEdit(job) } label: { Label("Edit schedule", systemImage: "calendar.badge.clock") }
                Button(role: .destructive) { onDelete(job) } label: { Label("Remove job", systemImage: "trash") }
            }
        }
    }

    private func blockLayout(for job: VisitDTO) -> (y: CGFloat, height: CGFloat) {
        let start = APIDateFormatting.parse(job.startAt) ?? day
        let end = APIDateFormatting.parse(job.endAt) ?? start.addingTimeInterval(3600)
        let startMinutes = minutesFromDayStart(start)
        let endMinutes = minutesFromDayStart(end)
        let clampedStart = min(max(startMinutes, 0), CGFloat(endHour - startHour) * 60)
        let clampedEnd = min(max(endMinutes, clampedStart + 20), CGFloat(endHour - startHour) * 60)
        let y = vPadding + clampedStart / 60 * hourHeight
        let height = max((clampedEnd - clampedStart) / 60 * hourHeight, 30)
        return (y, height)
    }

    private func minutesFromDayStart(_ date: Date) -> CGFloat {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return CGFloat(minutes - startHour * 60)
    }

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        let date = calendar.date(from: comps) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

private struct ScheduleTimelineBlock: View {
    let job: VisitDTO
    var colorMode: ScheduleColorMode
    var compact: Bool

    private var accent: Color { ScheduleColors.accentColor(for: job, mode: colorMode) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StormTheme.navy)
                    .lineLimit(1)
                if !compact {
                    if let customer = job.customer {
                        Text(customer.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(timeRange).font(.caption2).foregroundStyle(.secondary)
                        if let tech = job.assignedUser {
                            Text("· \(tech.name)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                } else {
                    Text(timeRange).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ScheduleColors.backgroundColor(for: job, mode: colorMode))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var timeRange: String {
        let startTime = APIDateFormatting.parse(job.startAt)?.formatted(date: .omitted, time: .shortened)
            ?? APIDateFormatting.displayString(from: job.startAt)
        let endTime = APIDateFormatting.parse(job.endAt)?.formatted(date: .omitted, time: .shortened)
            ?? APIDateFormatting.displayString(from: job.endAt)
        return "\(startTime) – \(endTime)"
    }
}

// MARK: - Shared row (also used by the Visits list)

struct ScheduleRow: View {
    let job: VisitDTO
    var colorMode: ScheduleColorMode = .technician

    private var accent: Color {
        ScheduleColors.accentColor(for: job, mode: colorMode)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(job.title)
                    .font(.headline)
                    .foregroundStyle(StormTheme.navy)

                if let customer = job.customer {
                    Text(customer.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(timeRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    StatusBadge(status: job.status)
                }

                HStack(spacing: 10) {
                    if let tech = job.assignedUser {
                        HStack(spacing: 6) {
                            EmployeeAvatar(person: tech, size: 22)
                            Text(tech.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Unassigned")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if colorMode != .area, let area = job.serviceArea {
                        Text(area.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: area.color ?? "#64748B")?.opacity(0.15) ?? StormTheme.ice.opacity(0.5))
                            .foregroundStyle(Color(hex: area.color ?? "#64748B") ?? StormTheme.navy)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(ScheduleColors.backgroundColor(for: job, mode: colorMode))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var timeRange: String {
        let start = APIDateFormatting.displayString(from: job.startAt)
        let end = APIDateFormatting.displayString(from: job.endAt)
        if Calendar.current.isDate(
            APIDateFormatting.parse(job.startAt) ?? Date(),
            inSameDayAs: APIDateFormatting.parse(job.endAt) ?? Date()
        ) {
            let startTime = APIDateFormatting.parse(job.startAt)?.formatted(date: .omitted, time: .shortened) ?? start
            let endTime = APIDateFormatting.parse(job.endAt)?.formatted(date: .omitted, time: .shortened) ?? end
            return "\(startTime) – \(endTime)"
        }
        return "\(start) – \(end)"
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        StormBadge(text: status.visitDisplayLabel, style: .accent)
    }
}
