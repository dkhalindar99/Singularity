// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Voice through LiveKit (livekit-client, Apache-2.0), loaded only when the
// server has voice set up, so an ink-only room never downloads it.
//
// SpaceNotes Live is ink and voice only: there are no cameras. The ticket
// from the room server allows the microphone and nothing else, so this module
// never asks for a camera. Voice costs a fraction of video and carries no
// faces (docs/research). Microphone on when you join; mute any time.

// Shipped with the app (web/vendor, see NOTICE.md) rather than fetched from a
// CDN, so a room never depends on a third-party site being reachable.
const LIVEKIT_URL = "/vendor/livekit-client/livekit-client.esm.mjs";

export class LiveVoice extends EventTarget {
  static async connect({ url, token, startWithMic = true }) {
    const lk = await import(LIVEKIT_URL);
    const voice = new LiveVoice(lk);
    await voice.#connect(url, token, startWithMic);
    return voice;
  }

  constructor(lk) {
    super();
    this.lk = lk;
    this.room = new lk.Room({
      dynacast: true,
      audioCaptureDefaults: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
      // Speech, not music: about 24 kbps instead of 48, with silence sent as
      // almost nothing (DTX). Half the mobile data for the same voice.
      publishDefaults: { audioPreset: lk.AudioPresets.speech, dtx: true },
    });
    this.speaking = new Set();
  }

  async #connect(url, token, startWithMic) {
    const { RoomEvent } = this.lk;
    const changed = () => this.dispatchEvent(new Event("change"));
    for (const event of [
      RoomEvent.TrackSubscribed, RoomEvent.TrackUnsubscribed, RoomEvent.TrackMuted, RoomEvent.TrackUnmuted,
      RoomEvent.LocalTrackPublished, RoomEvent.LocalTrackUnpublished, RoomEvent.ParticipantConnected,
      RoomEvent.ParticipantDisconnected, RoomEvent.Reconnected, RoomEvent.Disconnected,
      // Browsers block sound until the page has been touched; the join button
      // counts, but a later reconnect may need another tap.
      RoomEvent.AudioPlaybackStatusChanged,
    ]) this.room.on(event, changed);
    this.room.on(RoomEvent.ActiveSpeakersChanged, (speakers) => {
      this.speaking = new Set(speakers.map((p) => p.identity));
      changed();
    });
    await this.room.connect(url, token);
    if (startWithMic) await this.setMic(true).catch(() => {});
    changed();
  }

  get micEnabled() {
    return this.room.localParticipant.isMicrophoneEnabled;
  }

  get canPlayAudio() {
    return this.room.canPlaybackAudio;
  }

  startAudio() {
    return this.room.startAudio();
  }

  async setMic(on) {
    await this.room.localParticipant.setMicrophoneEnabled(on);
    this.dispatchEvent(new Event("change"));
  }

  #participant(uid) {
    if (this.room.localParticipant.identity === uid) return this.room.localParticipant;
    return this.room.remoteParticipants.get(uid) ?? null;
  }

  isMicOn(uid) {
    return this.#participant(uid)?.isMicrophoneEnabled ?? false;
  }

  isSpeaking(uid) {
    return this.speaking.has(uid);
  }

  /** Remote voices play through elements LiveKit creates; keep them in the page. */
  attachAudio(container) {
    const { RoomEvent, Track } = this.lk;
    // People who were already talking when we joined were subscribed during
    // connect(), before this listener existed; attach them too.
    for (const participant of this.room.remoteParticipants.values()) {
      for (const publication of participant.audioTrackPublications.values()) {
        if (publication.track) container.append(publication.track.attach());
      }
    }
    this.room.on(RoomEvent.TrackSubscribed, (track) => {
      if (track.kind === Track.Kind.Audio) container.append(track.attach());
    });
    this.room.on(RoomEvent.TrackUnsubscribed, (track) => {
      if (track.kind === Track.Kind.Audio) track.detach().forEach((el) => el.remove());
    });
  }

  disconnect() {
    return this.room.disconnect();
  }
}
