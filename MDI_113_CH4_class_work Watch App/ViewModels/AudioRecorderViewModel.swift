import Foundation
import Combine
import AVFoundation

struct Recording: Identifiable {
    let id = UUID()
    let url: URL // URL are locations is not necesarily tied to a network location, home/documents/file.mp3
    let duration: TimeInterval // TimeInterval != Double/Int
    let recordedDate: Date // ISO6001 standard for dates 2026-02-26T19:40:26.400-06:00
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60 // duration 10.4067
        let seconds = Int(duration) % 60
        
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        return formatter.string(from: recordedDate) // 2026/02/26 19:40
    }
}

class AudioRecorderViewModel: ObservableObject {
    // MARK: -- Published Properties
    @Published var isRecording: Bool = false
    @Published var recordingTime: TimeInterval = 0
    @Published var recordings: [Recording] = []
    @Published var errorMessage: String?
    @Published var permissionGranted: Bool = false
    
    
    // MARK: - Private Props
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    init() {
        loadRecordings()
    }
    
    func loadRecordings() {
        let fileManager = FileManager.default
        let documentsURL: URL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0] // urls -> ["user/documents/.."]
        
        do {
            let filesURLs = try fileManager.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            
            let recordingFiles = filesURLs.filter { url in
                // alexd/documents/superCoolVoiceMemoApp_recording_57684645745786487.m4a
                url.lastPathComponent.hasPrefix("superCoolVoiceMemoApp_recording_") && url.pathExtension == "m4a"
            }
            
            var loadedRecordings: [Recording] = []
            
            for fileURL in recordingFiles {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                let recordedDate = attributes[.creationDate] as? Date ?? Date()
                
                let duration: TimeInterval
                
                do {
                    let audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
                    duration = audioPlayer.duration
                } catch {
                    duration = 0
                }
                
                let recording =  Recording(
                    url: fileURL,
                    duration: duration,
                    recordedDate: recordedDate
                )
                
                loadedRecordings.append(recording)
            }
            
            // sort by date newest first
            recordings = loadedRecordings.sorted { $0.recordedDate > $1.recordedDate }
        } catch {
            errorMessage = "Failed to load recordings."
        }
        
    }


    
    // MARK: - Permission
    func checkPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            permissionGranted = false
        case .denied:
            permissionGranted = false
        case .granted:
            permissionGranted = true
        @unknown default:
            permissionGranted = false
        }
    }
    
    func requestPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
                
                if !granted {
                    self?.errorMessage = "Microphone Permission Required"
                }
            }
        }
    }
    
    // MARK: - Recording Methods
    func startRecording() {
        guard permissionGranted else {
            errorMessage = "Microphone Permission Required"
            return
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            let filename = "superCoolVoiceMemoApp_recording_\(Date().timeIntervalSince1970).m4a" // current date and time represented in milliseconds since jan 01 1970
            
            let fileURLWithName = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: fileURLWithName, settings: settings)
            audioRecorder?.record()
            
            isRecording = true
            recordingStartTime = Date()
            startTimer()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)" 
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        
        isRecording = false
        stopTimer()
        
        if let startTime = recordingStartTime, let url = audioRecorder?.url {
            let duration = Date().timeIntervalSince(startTime)
            let recording = Recording(
                url: url,
                duration: duration,
                recordedDate: Date()
            )
            recordings.insert(recording, at: 0)
        }
        
        recordingTime = 0
        recordingStartTime = nil
    }

    func deleteRecording(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]
            
            try? FileManager.default.removeItem(at: recording.url)
            
            recordings.remove(atOffsets:  offsets)
        }
    }
    
    func startTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            self.recordingTime = Date().timeIntervalSince(startTime)
        }
    }
    
    func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}
