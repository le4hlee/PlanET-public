//
//  GroupHeaderView.swift
//  PlanET
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import SwiftUI
import WidgetKit // NEW
import UserNotifications

// MARK: group
struct GroupHeaderView: View {
    let title: String
    let color: Color
    let count: Int
    @Binding var isExpanded: Bool
    
    var body: some View {
        Button(action: { withAnimation { isExpanded.toggle() }}) {
            HStack {
                Image(systemName: isExpanded ? "folder.open.fill" : "folder.fill")
                    .foregroundStyle(.secondary)
                Text(title).fontWeight(.medium)
                Spacer()
                Text("\(count)").font(.caption).padding(5).background(Color.white.opacity(0.5)).cornerRadius(5)
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .font(.caption)
            }
            .padding(8)
            .background(color)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
