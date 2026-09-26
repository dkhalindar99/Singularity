// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI

/// The row of people along the top: who is here, who is talking.
struct LiveParticipantStrip: View {
    let members: [Member]
    let me: You?
    @ObservedObject var voice: LiveVoiceObserver
    @Environment(\.liveTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(members) { member in
                    LiveParticipantTile(member: member,
                                        isMe: member.connectionId == me?.connectionId,
                                        provider: voice.provider)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(theme.background)
    }
}

/// One person: initials in their colour, name, host badge, microphone state,
/// a ring while they speak, and a raised hand.
struct LiveParticipantTile: View {
    let member: Member
    let isMe: Bool
    let provider: LiveVoiceProviding?
    @Environment(\.liveTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius)
        let speaking = provider?.isSpeaking(uid: member.uid) ?? false
        let micOn = provider?.isMicrophoneOn(uid: member.uid)
        VStack(spacing: 6) {
            Circle()
                .fill(Color(memberHex: member.color))
                .frame(width: 44, height: 44)
                .overlay(Text(liveInitials(member.name)).font(theme.label).foregroundColor(.white))
                .overlay(Circle().stroke(speaking ? theme.accent : Color.clear, lineWidth: 3).padding(-4))
                .animation(.easeOut(duration: 0.15), value: speaking)
            HStack(spacing: 4) {
                if let micOn {
                    Image(systemName: micOn ? "mic.fill" : "mic.slash.fill")
                        .imageScale(.small)
                        .foregroundColor(micOn ? theme.secondaryText : theme.danger)
                        .accessibilityLabel(micOn ? "Microphone on" : "Muted")
                }
                Text(isMe ? "\(member.name) (you)" : member.name)
                    .font(theme.caption)
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 108, height: 88)
        .background(shape.fill(theme.surface))
        .overlay(shape.stroke(speaking ? theme.accent : theme.divider, lineWidth: speaking ? 2 : 1))
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
                    .foregroundColor(theme.accent)
                    .padding(6)
                    .accessibilityLabel("Host")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(speaking ? .updatesFrequently : [])
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
