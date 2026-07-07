// PDFReportView.swift
// Vehicle Damage Investigation Assistant
// Embeds a PDFKit view to preview a generated forensic report and
// offers a share action to AirDrop / Mail / Save it.

import SwiftUI
import PDFKit

struct PDFReportView: View {
    let url: URL
    @State private var showShare = false

    var body: some View {
        PDFKitRepresentedView(url: url)
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                ActivityShareSheet(items: [url])
            }
    }
}

struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}
