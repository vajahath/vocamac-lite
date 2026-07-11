// TranscriptionResult.swift
// VocaMac Lite
//
// Represents the output of a VocaMac Lite transcription.

import Foundation

struct VocaTranscription: Identifiable {
    /// Unique identifier for this transcription
    let id: UUID

    /// The transcribed text
    let text: String

    /// Time taken to perform the transcription (seconds)
    let duration: TimeInterval

    /// Detected or specified language (ISO 639-1 code)
    let detectedLanguage: String

    /// When the transcription was performed
    let timestamp: Date

    /// Length of the source audio in seconds
    let audioLengthSeconds: Double

    /// Which model was used for this transcription (endpoint model name, or "remote" when unset)
    let modelUsed: String

    init(
        text: String,
        duration: TimeInterval,
        detectedLanguage: String,
        audioLengthSeconds: Double,
        modelUsed: String,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.text = text
        self.duration = duration
        self.detectedLanguage = detectedLanguage
        self.timestamp = timestamp
        self.audioLengthSeconds = audioLengthSeconds
        self.modelUsed = modelUsed
    }
}
