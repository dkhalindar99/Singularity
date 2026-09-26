// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI

/// The row of people along the top, like a video call.
struct LiveParticipantStrip: View {
    let members: [Member]
    let me: You?
    @ObservedObject var video: LiveVideoObserver
    @Environment(\.liveTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(members) { member in
                    LiveParticipantTile(member: member,
                                        isMe: member.connectionId == me?.connectionId,
                                        provider: video.provider)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(theme.background)
    }
}

struct LiveParticipantTile: View {
    let member: Member
    let isMe: Bool
    let provider: LiveVideoProviding?
    @Environment(\.liveTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius)
        let speaking = provider?.isSpeaking(uid: member.uid) ?? false
        ZStack {
            shape.fill(theme.tileBackground)
            if let video = provider?.videoView(uid: member.uid) {
                video.clipShape(shape)
            } else {
                Circle()
                    .fill(Color(memberHex: member.color))
                    .frame(width: 44, height: 44)
                    .overlay(Text(liveInitials(member.name)).font(theme.label).foregroundColor(.white))
            }
        }
        .frame(width: 132, height: 88)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                if let micOn = provider?.isMicrophoneOn(uid: member.uid) {
                    Image(systemName: micOn ? "mic.fill" : "mic.slash.fill")
                        .imageScale(.small)
                        .foregroundColor(micOn ? .white : theme.danger)
                }
                Text(isMe ? "\(member.name) (you)" : member.name)
                    .font(theme.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .padding(6)
        }
        .overlay(alignment: .topTrailing) {
            if member.handRaised {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(theme.handRaised)
                    .padding(6)
                    .accessibilityLabel("Hand raised")
            }
        }
        .overlay(alignment: .topLeading) {
            if member.isHost {
                Image(systemName: "star.fill")
                    .imageScale(.small)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(6)
                    .accessibilityLabel("Host")
            }
        }
        .overlay(shape.stroke(speaking ? theme.accent : Color.clear, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

/// Everyone in the room; for the host, who may draw and who stays.
struct LiveParticipantsSheet: View {
    @ObservedObject var client: RoomClient
    @Environment(\.liveTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if client.isHost {
                    Section("Who can write") {
                        Picker("Who can write", selection: policyBinding) {
                            Text("Everyone").tag(DrawPolicy.everyone)
                            Text("Only me").tag(DrawPolicy.host)
                            Text("Pen holder").tag(DrawPolicy.pen)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("In the room (\(client.members.count))") {
                    ForEach(client.members) { member in
                        row(member)
                    }
                }
            }
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var policyBinding: Binding<DrawPolicy> {
        Binding(
            get: { client.state.policy ?? .everyone },
            set: { policy in
                client.setPolicy(policy, penHolder: policy == .pen ? client.state.penHolder : nil)
            }
        )
    }

    private func row(_ member: Member) -> some View {
        let isMe = member.connectionId == client.me?.connectionId
        let holdsPen = client.state.policy == .pen && client.state.penHolder == member.uid
        return HStack(spacing: 12) {
            Circle()
                .fill(Color(memberHex: member.color))
                .frame(width: 32, height: 32)
                .overlay(Text(liveInitials(member.name)).font(theme.caption).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "\(member.name) (you)" : member.name)
                    .font(theme.body)
                    .foregroundColor(theme.primaryText)
                if member.isHost || holdsPen {
                    Text(member.isHost ? "Host" : "Has the pen")
                        .font(theme.caption)
                        .foregroundColor(theme.secondaryText)
                }
            }
            Spacer()
            if member.handRaised {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(theme.handRaised)
                    .accessibilityLabel("Hand raised")
            }
            if client.isHost && !member.isHost {
                Menu {
                    Button {
                        client.setPolicy(.pen, penHolder: member.uid)
                    } label: {
                        Label("Give the pen", systemImage: "pencil.tip")
                    }
                    Button(role: .destructive) {
                        client.remove(uid: member.uid)
                    } label: {
                        Label("Remove from room", systemImage: "person.fill.xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .foregroundColor(theme.accent)
                }
                .accessibilityLabel("Actions for \(member.name)")
            }
        }
    }
}
#endif
