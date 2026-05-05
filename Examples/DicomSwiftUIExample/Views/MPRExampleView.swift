//
//  MPRExampleView.swift
//  DicomSwiftUIExample
//
//  Created by Gemini CLI.
//

import SwiftUI
import DicomSwiftUI
import DicomCore

struct MPRExampleView: View {
    @StateObject private var viewModel = MPRViewModel()
    @State private var showingFolderPicker = false
    
    var body: some View {
        ZStack {
            if viewModel.volume != nil || viewModel.isLoading {
                MPRView(viewModel: viewModel)
            } else {
                emptyState
            }
        }
        .navigationTitle("Multi-Planar Reconstruction")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingFolderPicker = true }) {
                    Label("Select DICOM Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingFolderPicker) {
            folderPickerView
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.perspective")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("MPR Viewer")
                .font(.title)
            
            Text("Select a folder containing a CT or MRI series to visualize the volume from all axes.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Select DICOM Folder") {
                showingFolderPicker = true
            }
            .buttonStyle(.borderedProminent)
            
            // Helpful tip
            VStack(alignment: .leading, spacing: 8) {
                Label("Requires a series of images", systemImage: "info.circle")
                Label("Works best with CT scans", systemImage: "check.circle")
                Label("Corrects for slice spacing", systemImage: "aspectratio")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top)
        }
    }
    
    private var folderPickerView: some View {
        #if os(iOS)
        DocumentPickerView(configuration: .directory) { urls in
            if let url = urls.first {
                Task {
                    await viewModel.loadVolume(from: url)
                }
            }
            showingFolderPicker = false
        }
        #else
        MacOSFolderPicker { url in
            Task {
                await viewModel.loadVolume(from: url)
            }
            showingFolderPicker = false
        }
        #endif
    }
}

#if os(macOS)
import AppKit

struct MacOSFolderPicker: View {
    let onPick: (URL) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select DICOM Series Folder")
                .font(.headline)
            
            Button("Choose Folder...") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                
                if panel.runModal() == .OK {
                    if let url = panel.url {
                        onPick(url)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 300, height: 200)
    }
}
#endif
