//
//  VisionMPRExampleView.swift
//  DicomSwiftUIExample
//
//  Created by Gemini CLI.
//

import SwiftUI
import DicomSwiftUI
import DicomCore

/// A visionOS optimized wrapper for the MPR viewer.
struct VisionMPRExampleView: View {
    @StateObject private var viewModel = MPRViewModel()
    @State private var showingFolderPicker = false
    
    var body: some View {
        ZStack {
            if viewModel.volume != nil || viewModel.isLoading {
                MPRView(viewModel: viewModel)
                    // Add subtle glass effect to the MPR view
                    #if os(visionOS)
                    .glassBackgroundEffect()
                    #endif
            } else {
                emptyState
            }
        }
        .navigationTitle("Spatial MPR Viewer")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingFolderPicker = true }) {
                    Label("Select DICOM Folder", systemImage: "folder.badge.plus")
                        #if os(visionOS) || os(iOS)
                        .hoverEffect(.highlight)
                        #endif
                }
            }
        }
        .sheet(isPresented: $showingFolderPicker) {
            folderPickerView
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 30) {
            Image(systemName: "visionpro")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .symbolEffect(.pulse)
            
            Text("Spatial MPR Viewer")
                .font(.extraLargeTitle)
                .fontWeight(.bold)
            
            Text("Select a folder containing a CT or MRI series (like CORO_TC) to visualize the volume from all axes in your physical space.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
            
            Button("Select DICOM Folder") {
                showingFolderPicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            #if os(visionOS) || os(iOS)
            .hoverEffect(.lift)
            #endif
            
            // Helpful tip
            HStack(spacing: 20) {
                Label("Requires a series of images", systemImage: "info.circle")
                Label("Works best with CT scans", systemImage: "check.circle")
                Label("Pinch to zoom & pan", systemImage: "hand.draw")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.top, 20)
        }
        #if os(visionOS)
        .glassBackgroundEffect()
        #endif
        .padding(40)
    }
    
    private var folderPickerView: some View {
        #if os(iOS) || os(visionOS)
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
