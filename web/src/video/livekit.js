// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Voice and video through LiveKit (livekit-client, Apache-2.0), loaded only
// when a room actually has video, so an ink-only room never downloads it.
//
// Defaults follow the research (docs/research): microphone on, camera off;
// cameras at 360p with a 180p simulcast layer; adaptive stream so a small
// tile only receives the small layer; dynacast so nobody sends a layer no one
// watches. "Data saver" turns every camera off, your own included.

// Shipped with the app (web/vendor, see NOTICE.md) rather than fetched from a
// CDN, so a room never depends on a third-party site being reachable.
const LIVEKIT_URL = "/vendor/livekit-client/livekit-client.esm.mjs";

export class LiveVideo extends EventTarget {
  static async connect({ url, token, startWithMic = true }) {
    const lk = await import(LIVEKIT_URL);
    const video = new LiveVideo(lk);
    await video.#connect(url, token, startWithMic);
    return video;
  }

  constructor(lk) {
    super();
    this.lk = lk;
    this.room = new lk.Room({
      adaptiveStream: true,
      dynacast: true,
      videoCaptureDefaults: { resolution: lk.VideoPresets.h360.resolution },
      publishDefaults: { simulcast: true, videoSimulcastLayers: [lk.VideoPresets.h180] },
      audioCaptureDefaults: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    });
    this.speaking = new Set();
    this.dataSaver = false;
  }

  async #connect(url, token, startWithMic) {
    const { RoomEvent } = this.lk;
    const changed = () => this.dispatchEvent(new Event("change"));
    for (const event of [
      RoomEvent.TrackSubscribed, RoomEvent.TrackUnsubscribed, RoomEvent.TrackMuted, RoomEvent.TrackUnmuted,
      RoomEvent.LocalTrackPublished, RoomEvent.LocalTrackUnpublished, RoomEvent.ParticipantConnected,
      RoomEvent.ParticipantDisconnected, RoomEvent.Reconnected,
    ]) this.room.on(event, changed);
    this.room.on(RoomEvent.ActiveSpeakersChanged, (speakers) => {
      this.speaking = new Set(speakers.map((p) => p.identity));
      changed();
    });
    this.room.on(RoomEvent.Disconnected, changed);
    // Browsers block sound until the page has been touched; the join button
    // counts, but a later reconnect may need another tap.
    this.room.on(RoomEvent.AudioPlaybackStatusChanged, changed);
    await this.room.connect(url, token);
    if (startWithMic) await this.setMic(true).catch(() => {});
    changed();
  }

  get micEnabled() {
    return this.room.localParticipant.isMicrophoneEnabled;
  }

  get cameraEnabled() {
    return this.room.localParticipant.isCameraEnabled;
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

  async setCamera(on) {
    if (on && this.dataSaver) return;
    await this.room.localParticipant.setCameraEnabled(on);
    this.dispatchEvent(new Event("change"));
  }

  /** Data saver: no cameras in or out; voice stays. */
  async setDataSaver(on) {
    this.dataSaver = on;
    if (on && this.cameraEnabled) await this.room.localParticipant.setCameraEnabled(false);
    for (const participant of this.room.remoteParticipants.values()) {
      const publication = participant.getTrackPublication(this.lk.Track.Source.Camera);
      publication?.setSubscribed(!on);
    }
    this.dispatchEvent(new Event("change"));
  }

  #participant(uid) {
    if (this.room.localParticipant.identity === uid) return this.room.localParticipant;
    return this.room.remoteParticipants.get(uid) ?? null;
  }

  /** The camera track for a person, or null when their camera is off. */
  cameraTrack(uid) {
    const publication = this.#participant(uid)?.getTrackPublication(this.lk.Track.Source.Camera);
    return publication && !publication.isMuted && publication.track ? publication.track : null;
  }

  isMicOn(uid) {
    return this.#participant(uid)?.isMicrophoneEnabled ?? false;
  }

  isSpeaking(uid) {
    return this.speaking.has(uid);
  }

  /** Remote audio plays through elements LiveKit creates; keep them in the page. */
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
