import SwiftUI

/// A row of avatars to pick one seat: "Who knocked?", "Who's dealing?", the live knock and the
/// self-report knocker decision. The selected seat gets the red ring (plus `hand.raised` when
/// `marksKnocker`); the others dim once something is selected.
struct SeatPickerRow: View {
    let seats: [Seat]
    var selected: SeatID?
    var marksKnocker = false
    var size: AvatarView.Size = .compact
    /// Seats to show a progress ring on (the 5-second proposal ring), with its fraction 0…1.
    var ring: (seat: SeatID, fraction: Double)?
    let onSelect: (SeatID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(seats) { seat in
                    Button {
                        onSelect(seat.id)
                    } label: {
                        VStack(spacing: 4) {
                            AvatarView(seat: seat, size: size, ring: seat.id == selected ? .focus : .none)
                                .overlay(alignment: .topTrailing) {
                                    if marksKnocker && seat.id == selected {
                                        Image(systemName: "hand.raised.fill")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .background(.kedroRed, in: .circle)
                                            .offset(x: 6, y: -6)
                                    }
                                }
                                .overlay {
                                    if let ring, ring.seat == seat.id {
                                        Circle()
                                            .trim(from: 0, to: ring.fraction)
                                            .stroke(.kedroRed, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                            .rotationEffect(.degrees(-90))
                                            .padding(-7)
                                    }
                                }
                            Text(seat.displayName)
                                .font(.caption2)
                                .foregroundStyle(seat.id == selected ? Color.cream : Color.silver)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .opacity(selected == nil || seat.id == selected ? 1 : 0.55)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(seat.displayName + (seat.isGuest ? ", guest" : ""))
                    .accessibilityAddTraits(seat.id == selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    VStack {
        SeatPickerRow(seats: PreviewData.sampleSeats, selected: PreviewData.samSeat, marksKnocker: true) { _ in }
        SeatPickerRow(seats: PreviewData.sampleSeats, selected: nil) { _ in }
        SeatPickerRow(seats: PreviewData.sampleSeats, selected: PreviewData.anaSeat, ring: (PreviewData.anaSeat, 0.6)) { _ in }
    }
    .background(.night)
    .previewEnvironment()
}
