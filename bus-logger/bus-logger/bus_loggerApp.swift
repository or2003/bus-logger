//
//  bus_loggerApp.swift
//  bus-logger
//
//  Created by or_cohen on 29/08/2025.
//

import SwiftUI
import CoreMotion
import CoreLocation

class MotionLogger: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motion = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var fileHandle: FileHandle?
    private var currentSessionStart: Date?
    private var currentFilePath: String?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }

    func startLogging() {
        currentSessionStart = Date()
        
        // Create CSV file with timestamp in name
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: currentSessionStart!)
        let fileName = "bus_ride_\(timestamp).csv"
        let logURL = docs.appendingPathComponent(fileName)
        currentFilePath = logURL.path
        
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logURL)
        fileHandle?.write("time,ax,ay,az,gx,gy,gz,lat,lon,speed\n".data(using: .utf8)!)

        // Start motion updates
        motion.deviceMotionUpdateInterval = 1.0 / 50.0 // 50Hz
        motion.startDeviceMotionUpdates(to: .main) { data, error in
            guard let d = data else { return }
            let t = Date().timeIntervalSince1970
            let ua = d.userAcceleration
            let gr = d.rotationRate
            let lat = self.locationManager.location?.coordinate.latitude ?? 0
            let lon = self.locationManager.location?.coordinate.longitude ?? 0
            let spd = self.locationManager.location?.speed ?? 0

            let line = String(format: "%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.6f,%.6f,%.2f\n",
                              t, ua.x, ua.y, ua.z,
                              gr.x, gr.y, gr.z,
                              lat, lon, spd)
            self.fileHandle?.write(line.data(using: .utf8)!)
        }

        locationManager.startUpdatingLocation()
    }

    func stopLogging() {
        motion.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
        try? fileHandle?.close()
        
        // Save session to Core Data
        if let startTime = currentSessionStart, let filePath = currentFilePath {
            let context = PersistenceController.shared.container.viewContext
            let newItem = Item(context: context)
            newItem.timestamp = startTime
            
            do {
                try context.save()
                print("Saved session: \(filePath)")
            } catch {
                print("Failed to save session: \(error)")
            }
        }
        
        currentSessionStart = nil
        currentFilePath = nil
        fileHandle = nil
    }
    
    func isMotionAvailable() -> Bool {
        return CMMotionManager().isDeviceMotionAvailable
    }
}

@main
struct bus_loggerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            BusLoggerMainView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

struct BusLoggerMainView: View {
    @StateObject var logger = MotionLogger()
    @State private var isLogging = false
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
        animation: .default)
    private var sessions: FetchedResults<Item>

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                Text("Bus Logger")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                // Recording Controls
                VStack(spacing: 15) {
                    Button(action: {
                        if isLogging {
                            logger.stopLogging()
                        } else {
                            logger.startLogging()
                        }
                        isLogging.toggle()
                    }) {
                        HStack {
                            Image(systemName: isLogging ? "stop.fill" : "play.fill")
                            Text(isLogging ? "Stop Recording" : "Start Recording")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isLogging ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!logger.isMotionAvailable())
                    
                    if isLogging {
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                            Text("Recording IMU data...")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Sessions List
                if !sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recorded Sessions")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        List {
                            ForEach(sessions) { session in
                                SessionRowView(session: session)
                            }
                            .onDelete(perform: deleteSessions)
                        }
                        .listStyle(InsetGroupedListStyle())
                    }
                } else {
                    Spacer()
                    Text("No sessions recorded yet")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private func deleteSessions(offsets: IndexSet) {
        withAnimation {
            offsets.map { sessions[$0] }.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                print("Failed to delete session: \(error)")
            }
        }
    }
}

struct SessionRowView: View {
    let session: Item
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bus Ride")
                    .font(.headline)
                Text(session.timestamp!, formatter: sessionFormatter)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

private let sessionFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()
