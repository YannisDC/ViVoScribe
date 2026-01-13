import SwiftUI

struct QandAView: View {
    let transcriptionText: String
    @StateObject private var analyzer = TranscriptionAnalyzer()
    @State private var question: String = ""
    @State private var answer: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Q&A")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Content
            VStack(spacing: 16) {
                // Question input area
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ask a question about the transcript")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .bottom, spacing: 8) {
                        TextEditor(text: $question)
                            .font(.body)
                            .frame(minHeight: 80, maxHeight: 120)
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separatorColor), lineWidth: 1)
                            )
                        
                        Button(action: askQuestion) {
                            if isProcessing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                    }
                }
                .padding()
                
                Divider()
                
                // Answer area
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Answer")
                            .font(.headline)
                        
                        Spacer()
                        
                        if !answer.isEmpty {
                            Button(action: { answer = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if isProcessing {
                        HStack {
                            ProgressView()
                            Text("Thinking...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else if let error = errorMessage {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .padding()
                    } else if answer.isEmpty {
                        Text("Ask a question to get started")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ScrollView {
                            Text(answer)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                    }
                }
                .padding()
                
                Spacer()
            }
        }
        .frame(width: 600, height: 500)
    }
    
    private func askQuestion() {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isProcessing = true
        errorMessage = nil
        answer = ""
        
        Task {
            do {
                let response = try await analyzer.answerQuestion(
                    about: transcriptionText,
                    question: question
                )
                
                await MainActor.run {
                    answer = response
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}
