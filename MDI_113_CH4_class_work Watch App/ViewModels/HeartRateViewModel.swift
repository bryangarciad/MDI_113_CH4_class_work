import Foundation
import HealthKit
import Combine

class HeartRateViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentHearthRate: Int = 0
    @Published var isMonitoring: Bool = false
    @Published var errorMessage: String?
    @Published var authorizationStatus: String = "Not Determined"
    
    // MARK: - Private Properties
    private let healthStore = HKHealthStore()
    private let heartRateQuery: HKQuery?
    
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let heartRateUnit = HKUnit.count().unitDivided(by: .minute()) // count is the quantity value divided by minute (Beats Per Minute BPMs)
    
    init() {
        checkAuthorizationStatus()
    }
    
    deinit() {
        stopMonitoring()
    }
    
    //MARK: - Auth
    private func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "health kit is not available"
            return
        }
        
        let status = healthStore.authorizationStatus(for: heartRateType)
        
        switch status {
        case .notDetermined:
            authorizationStatus = "Not Determined"
        case .sharingDenied:
            authorizationStatus = "Denied"
            errorMessage = "Pleas enable heart rate in settings to access this feature"
        case .sharingAuthorized:
            authorizationStatus = "Authorized"
        @unknown default:
            authorizationStatus = "Unknown"
        }
    }
    
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "health kit is not available"
            return
        }
        
        healthStore.requestAuthorization(toShare: nil, read: [heartRateType]) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self.authorizationStatus = "Authorized"
                    self.errorMessage = nil
                } else {
                    self.errorMessage = "Authorization Failed"
                }
            }
        }
    }
    
    // MARK: - Public Methods
    func startMonitorinHeartRate() {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "health kit is not available"
            return
        }
        
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            guard let samples = samples as? [HKQuantitySample], let sample = samples.last else { // two checks first check that samples is not empty or nil, second check verify that the sample size > 1
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error while getting the samples"
                    }
                }
                return
            }
            
            let heartRate = sample.quantity.doubleValue(for: self.heartRateUnit) // double represented in bpms
            
            DispatchQueue.main.async {
                self.currentHearthRate = Int(heartRate)
                self.errorMessage = nil
            }
            
        }
        
        heartRateQuery = query
        healthStore.execute(query)
        isMonitoring = true
    }
    
    func stopMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        
        isMonitoring = false
    }
}
