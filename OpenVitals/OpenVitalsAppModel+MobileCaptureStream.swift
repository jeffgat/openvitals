import Foundation

extension OpenVitalsAppModel {
  var mobileCaptureStreamReady: Bool {
    mobileCaptureStreamEnabled && validatedMobileCaptureStreamEndpoint() != nil
  }

  var shouldRouteOvernightFramesToMobileCaptureStream: Bool {
    mobileCaptureStreamReady && overnightGuardActive && overnightGuardSession != nil
  }

  func setMobileCaptureStreamEnabled(_ enabled: Bool) {
    mobileCaptureStreamEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: Self.mobileCaptureStreamEnabledDefaultsKey)
    configureMobileCaptureStreamQueue()
    if enabled, overnightGuardActive {
      overnightGuardRangePollWorkItem?.cancel()
      overnightGuardRangePollWorkItem = nil
      overnightGuardStatus = "Mac Stream active; range polls paused"
      refreshOvernightReadiness(reason: "mac_stream_enabled_range_poll_paused")
      writeOvernightGuardStatus(reason: "mac_stream_enabled_range_poll_paused")
    }
    ble.record(source: "mobile.capture_stream", title: enabled ? "enabled" : "disabled")
  }

  func setMobileCaptureStreamEndpoint(_ endpoint: String) {
    mobileCaptureStreamEndpoint = endpoint
    UserDefaults.standard.set(endpoint, forKey: Self.mobileCaptureStreamEndpointDefaultsKey)
    configureMobileCaptureStreamQueue()
  }

  func setMobileCaptureStreamToken(_ token: String) {
    mobileCaptureStreamToken = token
    UserDefaults.standard.set(token, forKey: Self.mobileCaptureStreamTokenDefaultsKey)
    configureMobileCaptureStreamQueue()
  }

  func configureMobileCaptureStreamQueue() {
    let endpointURL = validatedMobileCaptureStreamEndpoint()
    let enabled = mobileCaptureStreamEnabled && endpointURL != nil
    mobileCaptureStreamQueue.update(
      enabled: enabled,
      endpointURL: endpointURL,
      token: mobileCaptureStreamToken
    )

    if !mobileCaptureStreamEnabled {
      mobileCaptureStreamStatus = "Mac stream disabled"
      mobileCaptureStreamQueuedFrameCount = 0
    } else if endpointURL == nil {
      mobileCaptureStreamStatus = "Mac stream needs an HTTP endpoint"
    } else {
      mobileCaptureStreamStatus = "Mac stream ready"
    }
  }

  func streamCapturedFrameRows(_ rows: [CapturedFrameWriteRow], capture: ActiveHealthPacketCapture) {
    streamCapturedFrameRows(rows, session: mobileCaptureStreamSession(for: capture))
  }

  func streamCapturedFrameRows(_ rows: [CapturedFrameWriteRow], session: MobileCaptureStreamSession) {
    guard mobileCaptureStreamReady, !rows.isEmpty else {
      return
    }
    let result = mobileCaptureStreamQueue.enqueue(
      rows: rows,
      session: session
    )
    mobileCaptureStreamAcceptedFrameCount += result.acceptedFrameCount
    mobileCaptureStreamDroppedFrameCount += result.droppedFrameCount
    mobileCaptureStreamQueuedFrameCount = result.queuedRowCount
    if session.source == "ios.overnight_guard" {
      overnightGuardMobileStreamAcceptedFrameCount += result.acceptedFrameCount
    }

    if result.droppedFrameCount > 0 {
      mobileCaptureStreamStatus = "Mac stream queue full; dropped \(result.droppedFrameCount)"
      ble.record(
        level: .warn,
        source: "mobile.capture_stream",
        title: "queue_dropped",
        body: "accepted=\(result.acceptedFrameCount) dropped=\(result.droppedFrameCount) queued=\(result.queuedRowCount)/\(result.maxQueuedRows)"
      )
    } else if result.acceptedFrameCount > 0 {
      mobileCaptureStreamStatus = "Mac stream queued \(result.acceptedFrameCount) frames"
    }
  }

  func activeMobileCaptureFrameStreamSession() -> MobileCaptureStreamSession? {
    guard mobileCaptureStreamReady else {
      return nil
    }
    if let capture = activeHealthPacketCapture {
      return mobileCaptureStreamSession(for: capture)
    }
    if shouldRouteOvernightFramesToMobileCaptureStream,
       let session = overnightGuardSession {
      return mobileCaptureStreamSession(for: session)
    }
    return nil
  }

  func finishMobileCaptureStream(capture: ActiveHealthPacketCapture, endedAt: Date) {
    guard mobileCaptureStreamReady else {
      return
    }
    mobileCaptureStreamQueue.finish(
      sessionID: capture.sessionID,
      endedAtUnixMS: unixMilliseconds(endedAt),
      frameCount: capture.importedFrameCount
    )
  }

  func finishOvernightMobileCaptureStream(sessionID: String, endedAt: Date) {
    guard mobileCaptureStreamReady, overnightGuardMobileStreamAcceptedFrameCount > 0 else {
      return
    }
    mobileCaptureStreamQueue.finish(
      sessionID: sessionID,
      endedAtUnixMS: unixMilliseconds(endedAt),
      frameCount: overnightGuardMobileStreamAcceptedFrameCount
    )
  }

  func handleMobileCaptureStreamResult(_ result: MobileCaptureStreamResult) {
    mobileCaptureStreamSentFrameCount += result.sentFrameCount
    mobileCaptureStreamImportedFrameCount += result.importedFrameCount
    mobileCaptureStreamExistingFrameCount += result.existingFrameCount
    mobileCaptureStreamRawInsertedCount += result.rawInserted
    mobileCaptureStreamRawExistingCount += result.rawExisting
    mobileCaptureStreamQueuedFrameCount = result.queuedRowCount

    if let errorDescription = result.errorDescription {
      mobileCaptureStreamStatus = "\(result.status): \(errorDescription)"
      ble.record(level: .warn, source: "mobile.capture_stream", title: "send.failed", body: errorDescription)
    } else if result.kind == "finish" {
      mobileCaptureStreamStatus = result.status
      ble.record(source: "mobile.capture_stream", title: "finish.sent")
    } else {
      mobileCaptureStreamStatus = "\(result.status) | imported \(result.importedFrameCount) existing \(result.existingFrameCount)"
    }
  }

  private func validatedMobileCaptureStreamEndpoint() -> URL? {
    let text = mobileCaptureStreamEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: text),
          let scheme = url.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          url.host?.isEmpty == false else {
      return nil
    }
    return url
  }

  private func mobileCaptureStreamSession(for capture: ActiveHealthPacketCapture) -> MobileCaptureStreamSession {
    MobileCaptureStreamSession(
      sessionID: capture.sessionID,
      source: "ios.health_packet_capture",
      startedAtUnixMS: unixMilliseconds(capture.startedAt),
      deviceModel: capture.deviceModel,
      activeDeviceID: capture.activeDeviceID,
      provenance: capture.streamProvenance
    )
  }

  private func mobileCaptureStreamSession(for session: OvernightGuardSession) -> MobileCaptureStreamSession {
    let provenance = [
      "surface": "MoreStreamProbeViews",
      "capture_mode": session.decodedCaptureEnabled ? "overnight_guard_decoded_capture" : "overnight_guard_lean_raw_spool",
      "purpose": "historical_catch_up_stream",
      "transport": "ios_to_mac_mobile_ingest",
      "raw_spool_enabled": "true",
    ]
    return MobileCaptureStreamSession(
      sessionID: session.id,
      source: "ios.overnight_guard",
      startedAtUnixMS: unixMilliseconds(session.startedAt),
      deviceModel: ble.modelNumber ?? ble.activeDeviceName,
      activeDeviceID: ble.activeDeviceIdentifier?.uuidString,
      provenance: provenance
    )
  }
}
