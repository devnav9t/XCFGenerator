//
//  ContentView.swift
//  XCFGenerator
//
//  Created by Navneet Singh on 16/06/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedFolderPath: String = ""
    @State private var detectedScheme: String = ""
    @State private var isBuilding: Bool = false
    @State private var buildOutput: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var alertTitle: String = ""
    @State private var showOverwriteAlert: Bool = false
    @State private var pendingXCFrameworkPath: String = ""
    @State private var outputFolderBookmark: Data?
    @State private var outputFolderPath: String = ""
    @State private var showSuccessAlert: Bool = false
    @State private var lastXCFrameworkPath: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("XCFramework Generator")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            // Folder Selection Section
            GroupBox(label: Text("Project Folder").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(selectedFolderPath.isEmpty ? "No folder selected" : selectedFolderPath)
                            .foregroundColor(selectedFolderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Button("Select Folder") {
                            selectFolder()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    if !detectedScheme.isEmpty {
                        Text("Detected Scheme: \(detectedScheme)")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    }
                }
                .padding()
            }
            
            // Output Folder Selection Section
            GroupBox(label: Text("Output Folder").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(outputFolderPath.isEmpty ? "No output folder selected" : outputFolderPath)
                            .foregroundColor(outputFolderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Button("Select Output Folder") {
                            selectOutputFolder()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            
            // Build Button
            Button(action: {
                buildXCFramework()
            }) {
                HStack {
                    if isBuilding {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isBuilding ? "Building..." : "Build XCFramework")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedFolderPath.isEmpty || detectedScheme.isEmpty || outputFolderPath.isEmpty || isBuilding)
            
            // Output Section
            GroupBox(label: Text("Build Output").font(.headline)) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading) {
                            Text(buildOutput.isEmpty ? "Build output will appear here..." : buildOutput)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(buildOutput.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .id("BOTTOM")
                        }
                    }
                    .frame(height: 200)
                    .onChange(of: buildOutput) {
                        withAnimation {
                            scrollProxy.scrollTo("BOTTOM", anchor: .bottom)
                        }
                    }
                }
            }

            
            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 600)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Build Successful", isPresented: $showSuccessAlert) {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: lastXCFrameworkPath)])
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("XCFramework was created successfully at:\n\(lastXCFrameworkPath)")
        }
        .alert("XCFramework Already Exists", isPresented: $showOverwriteAlert) {
            Button("Cancel") {
                pendingXCFrameworkPath = ""
            }
            Button("Overwrite") {
                overwriteAndBuild()
            }
        } message: {
            Text("An XCFramework with the same name already exists. Do you want to overwrite it?")
        }
        .onAppear {
            loadOutputFolderBookmark()
        }
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select the folder containing your .xcodeproj file"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                selectedFolderPath = url.path
                detectScheme()
            }
        }
    }
    
    func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select the output folder for XCFramework"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                // Start accessing the security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    showError("Failed to access the selected folder")
                    return
                }
                
                // Create security-scoped bookmark
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    
                    // Save bookmark to UserDefaults
                    UserDefaults.standard.set(bookmarkData, forKey: "OutputFolderBookmark")
                    
                    outputFolderBookmark = bookmarkData
                    outputFolderPath = url.path
                    
                    appendOutput("Output folder selected: \(url.path)\n")
                } catch {
                    showError("Failed to create bookmark: \(error.localizedDescription)")
                }
                
                // Stop accessing the security-scoped resource
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
    
    func loadOutputFolderBookmark() {
        if let bookmarkData = UserDefaults.standard.data(forKey: "OutputFolderBookmark") {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if isStale {
                    // Bookmark is stale, user needs to reselect
                    UserDefaults.standard.removeObject(forKey: "OutputFolderBookmark")
                    outputFolderBookmark = nil
                    outputFolderPath = ""
                } else {
                    outputFolderBookmark = bookmarkData
                    outputFolderPath = url.path
                }
            } catch {
                // Failed to resolve bookmark, remove it
                UserDefaults.standard.removeObject(forKey: "OutputFolderBookmark")
                outputFolderBookmark = nil
                outputFolderPath = ""
            }
        }
    }
    
    func accessOutputFolder<T>(_ operation: (String) -> T) -> T? {
        guard let bookmarkData = outputFolderBookmark else {
            showError("No output folder selected")
            return nil
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            guard url.startAccessingSecurityScopedResource() else {
                showError("Failed to access output folder")
                return nil
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            return operation(url.path)
        } catch {
            showError("Failed to access output folder: \(error.localizedDescription)")
            return nil
        }
    }
    
    func detectScheme() {
        detectedScheme = ""
        
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: selectedFolderPath)
            
            guard let xcodeprojFile = contents.first(where: { $0.hasSuffix(".xcodeproj") }) else {
                showError("No .xcodeproj file found in the selected folder")
                return
            }
            
            let xcodeprojPath = "\(selectedFolderPath)/\(xcodeprojFile)"
            let schemesPath = "\(xcodeprojPath)/xcshareddata/xcschemes"
            
            if fileManager.fileExists(atPath: schemesPath) {
                let schemes = try fileManager.contentsOfDirectory(atPath: schemesPath)
                
                if let firstScheme = schemes.first(where: { $0.hasSuffix(".xcscheme") }) {
                    detectedScheme = String(firstScheme.dropLast(9)) // Remove .xcscheme extension
                } else {
                    showError("No schemes found in the project")
                }
            } else {
                showError("No shared schemes found. Please ensure your scheme is shared in Xcode")
            }
        } catch {
            showError("Error accessing project: \(error.localizedDescription)")
        }
    }
    
    func buildXCFramework() {
        guard !selectedFolderPath.isEmpty && !detectedScheme.isEmpty && !outputFolderPath.isEmpty else { return }
        
        accessOutputFolder { outputBasePath in
            let outputPath = "\(outputBasePath)/output"
            let xcframeworkPath = "\(outputPath)/\(detectedScheme).xcframework"
            
            // Check if XCFramework already exists
            if FileManager.default.fileExists(atPath: xcframeworkPath) {
                pendingXCFrameworkPath = xcframeworkPath
                DispatchQueue.main.async {
                    self.showOverwriteAlert = true
                }
                return
            }
            
            executeBuildCommands(outputBasePath: outputBasePath)
        }
    }
    
    func overwriteAndBuild() {
        accessOutputFolder { outputBasePath in
            // Remove existing XCFramework
            do {
                try FileManager.default.removeItem(atPath: pendingXCFrameworkPath)
                appendOutput("Removed existing XCFramework\n")
            } catch {
                showError("Failed to remove existing XCFramework: \(error.localizedDescription)")
                return
            }
            
            pendingXCFrameworkPath = ""
            executeBuildCommands(outputBasePath: outputBasePath)
        }
    }
    
    func executeBuildCommands(outputBasePath: String) {
        isBuilding = true
        buildOutput = ""
        
        let outputPath = "\(outputBasePath)/output"
        
        // Create output directory
        createOutputDirectory(outputPath)
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Change to project directory
            let projectPath = selectedFolderPath
            
            // Command 1: Build for iOS
            let iosCommand = """
            cd "\(projectPath)" && xcodebuild archive \\
            -scheme \(detectedScheme) \\
            -destination "generic/platform=iOS" \\
            -archivePath "\(outputPath)/\(detectedScheme)IOS" \\
            SKIP_INSTALL=NO \\
            BUILD_LIBRARY_FOR_DISTRIBUTION=YES
            """
            
            appendOutput("Building for iOS...\n")
            if !executeCommand(iosCommand) {
                DispatchQueue.main.async {
                    self.isBuilding = false
                }
                return
            }
            
            // Command 2: Build for iOS Simulator
            let simCommand = """
            cd "\(projectPath)" && xcodebuild archive \\
            -scheme \(detectedScheme) \\
            -destination "generic/platform=iOS Simulator" \\
            -archivePath "\(outputPath)/\(detectedScheme)SIM" \\
            SKIP_INSTALL=NO \\
            BUILD_LIBRARY_FOR_DISTRIBUTION=YES
            """
            
            appendOutput("Building for iOS Simulator...\n")
            if !executeCommand(simCommand) {
                DispatchQueue.main.async {
                    self.isBuilding = false
                }
                return
            }
            
            // Command 3: Create XCFramework
            let xcframeworkCommand = """
            cd "\(projectPath)" && xcodebuild -create-xcframework \\
            -framework "\(outputPath)/\(detectedScheme)IOS.xcarchive/Products/Library/Frameworks/\(detectedScheme).framework" \\
            -framework "\(outputPath)/\(detectedScheme)SIM.xcarchive/Products/Library/Frameworks/\(detectedScheme).framework" \\
            -output "\(outputPath)/\(detectedScheme).xcframework"
            """
            
            appendOutput("Creating XCFramework...\n")
            if executeCommand(xcframeworkCommand) {
                appendOutput("✅ XCFramework created successfully!\n")
                appendOutput("Output location: \(outputPath)/\(detectedScheme).xcframework\n")

                DispatchQueue.main.async {
                    self.lastXCFrameworkPath = "\(outputPath)/\(detectedScheme).xcframework"
                    self.showSuccessAlert = true
                    self.isBuilding = false
                }
            }
            
        }
    }
    
    func createOutputDirectory(_ path: String) {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: path) {
            do {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                appendOutput("Created output directory: \(path)\n")
            } catch {
                showError("Failed to create output directory: \(error.localizedDescription)")
            }
        }
    }
    
    func executeCommand(_ command: String) -> Bool {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", command]

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            if let output = String(data: handle.availableData, encoding: .utf8), !output.isEmpty {
                appendOutput(output)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            if let output = String(data: handle.availableData, encoding: .utf8), !output.isEmpty {
                appendOutput("Error: \(output)")
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            appendOutput("❌ Failed to execute command: \(error.localizedDescription)\n")
            return false
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        if process.terminationStatus != 0 {
            appendOutput("❌ Command failed with exit code: \(process.terminationStatus)\n")
            return false
        }

        return true
    }

    
    func appendOutput(_ text: String) {
        DispatchQueue.main.async {
            self.buildOutput += text
        }
    }
    
    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.alertTitle = "Error"
            self.alertMessage = message
            self.showAlert = true
        }
    }
    
}
