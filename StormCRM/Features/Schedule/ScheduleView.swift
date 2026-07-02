import SwiftUI

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published var jobs: [VisitDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(api: APIClient, around date: Date = Date()) async {
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
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func jobCount(on day: Date, calendar: Calendar = .current) -> Int {
        let target = calendar.startOfDay(for: day)
        return jobs.filter { job in
            guard let start = APIDateFormatting.parse(job.startAt) else { return false }
            return calendar.isDate(start, inSameDayAs: target)
        }.count
    }
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
    @State private var colorMode: ScheduleColorMode = .technician
    @State private var jobToEdit: VisitDTO?
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { Calendar.current }

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
            ?? calendar.startOfDay(for: selectedDate)
    }

    private var canEditSchedule: Bool {
        env.auth.user.map { UserRoles.canEditVisitOfficeFields($0.role) } ?? false
    }

    private var jobsForSelectedDay: [VisitDTO] {
        let day = calendar.startOfDay(for: selectedDate)
        return viewModel.jobs
            .filter { job in
                guard let start = APIDateFormatting.parse(job.startAt) else { return false }
                return calendar.isDate(start, inSameDayAs: day)
            }
            .sorted {
                let left = APIDateFormatting.parse($0.startAt) ?? .distantFuture
                let right = APIDateFormatting.parse($1.startAt) ?? .distantFuture
                return left < right
            }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScheduleWeekStrip(
                    selectedDate: $selectedDate,
                    weekStart: weekStart,
                    jobCount: { viewModel.jobCount(on: $0, calendar: calendar) }
                ) { delta in
                    shiftWeek(by: delta)
                }

                Divider()

                Group {
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
                    } else if jobsForSelectedDay.isEmpty {
                        ContentUnavailableView(
                            "No jobs",
                            systemImage: "calendar",
                            description: Text("Nothing scheduled for \(selectedDayLabel).")
                        )
                    } else {
                        List {
                            ForEach(jobsForSelectedDay) { job in
                                scheduleRow(for: job)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle(canEditSchedule ? "Schedule" : "My Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !calendar.isDateInToday(selectedDate) {
                        Button("Today") {
                            selectedDate = calendar.startOfDay(for: Date())
                            Task { await viewModel.load(api: env.apiClient, around: selectedDate) }
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
            .navigationDestination(for: VisitDTO.self) { job in
                VisitDetailView(visitId: job.id)
            }
            .refreshable { await viewModel.load(api: env.apiClient, around: selectedDate) }
            .task { await viewModel.load(api: env.apiClient, around: selectedDate) }
            .onChange(of: selectedDate) { _, newDate in
                Task { await viewModel.load(api: env.apiClient, around: newDate) }
            }
            .sheet(item: $jobToEdit) { job in
                ScheduleJobEditSheet(job: job) {
                    await viewModel.load(api: env.apiClient, around: selectedDate)
                }
            }
        }
        .background(StormTheme.page.ignoresSafeArea())
    }

    private var selectedDayLabel: String {
        if calendar.isDateInToday(selectedDate) { return "today" }
        if calendar.isDateInTomorrow(selectedDate) { return "tomorrow" }
        if calendar.isDateInYesterday(selectedDate) { return "yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func shiftWeek(by delta: Int) {
        guard let newWeekStart = calendar.date(byAdding: .weekOfYear, value: delta, to: weekStart),
              let weekday = calendar.dateComponents([.weekday], from: selectedDate).weekday,
              let newSelected = calendar.date(bySetting: .weekday, value: weekday, of: newWeekStart)
        else { return }
        selectedDate = calendar.startOfDay(for: newSelected)
    }

    @ViewBuilder
    private func scheduleRow(for job: VisitDTO) -> some View {
        NavigationLink(value: job) {
            ScheduleRow(job: job, colorMode: colorMode)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contextMenu {
            if canEditSchedule {
                Button {
                    jobToEdit = job
                } label: {
                    Label("Edit schedule", systemImage: "calendar.badge.clock")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEditSchedule {
                Button {
                    jobToEdit = job
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(StormTheme.sky)
            }
        }
    }
}

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
