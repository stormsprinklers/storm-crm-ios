import SwiftUI

struct HLPreviewProgress: View {
    @ObservedObject var model: HolidayQuoteViewModel
    var body: some View {
        if let progress = model.previewProgress {
            VStack(spacing: 6) {
                HStack {
                    if model.previewComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolEffect(.bounce, value: model.previewComplete)
                    } else { ProgressView().controlSize(.small) }
                    Text(model.previewStage).font(.caption.weight(.semibold))
                    Spacer()
                }
                ProgressView(value: progress).tint(model.previewComplete ? .green : .accentColor)
            }
            .foregroundStyle(model.previewComplete ? Color.green : Color.primary)
            .padding(12).background(.regularMaterial)
            .animation(.easeInOut, value: progress)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
