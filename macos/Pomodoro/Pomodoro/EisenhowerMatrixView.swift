import SwiftUI

struct EisenhowerMatrixView: View {
    let tasks: [TodoItem]
    let onSelectTask: (TodoItem) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            quadrantCard(
                title: "Do First",
                subtitle: "Important • Urgent",
                color: .red,
                tasks: tasks.filter { $0.matrixQuadrant == .doFirst }
            )
            quadrantCard(
                title: "Schedule",
                subtitle: "Important • Not Urgent",
                color: .blue,
                tasks: tasks.filter { $0.matrixQuadrant == .schedule }
            )
            quadrantCard(
                title: "Delegate",
                subtitle: "Not Important • Urgent",
                color: .orange,
                tasks: tasks.filter { $0.matrixQuadrant == .delegate }
            )
            quadrantCard(
                title: "Eliminate",
                subtitle: "Not Important • Not Urgent",
                color: .gray,
                tasks: tasks.filter { $0.matrixQuadrant == .eliminate }
            )
        }
    }

    private func quadrantCard(title: String, subtitle: String, color: Color, tasks: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                Text("No tasks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            } else {
                ForEach(tasks) { task in
                    Button {
                        onSelectTask(task)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if let dueDate = task.dueDate {
                                Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(color.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

private extension TodoItem {
    enum MatrixQuadrant {
        case doFirst
        case schedule
        case delegate
        case eliminate
    }

    var matrixQuadrant: MatrixQuadrant {
        let isImportant = priority == .high || priority == .medium
        let isUrgent: Bool
        if let dueDate {
            isUrgent = dueDate.timeIntervalSinceNow <= 48 * 60 * 60
        } else {
            isUrgent = false
        }

        switch (isImportant, isUrgent) {
        case (true, true):
            return .doFirst
        case (true, false):
            return .schedule
        case (false, true):
            return .delegate
        case (false, false):
            return .eliminate
        }
    }
}
