import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import Combine
import ReplayKit
import AVKit
import AVFoundation
import Charts
import Vision

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Quiz Game Models
enum QuestionType {
    case multipleChoice
    case trueFalse
    case shortAnswer
}

struct QuizQuestion: Identifiable {
    let id = UUID()
    let number: Int
    let question: String
    let type: QuestionType
    let options: [String] // For multiple choice and true/false
    let correctAnswer: String
}

struct QuizResult {
    let totalQuestions: Int
    let correctAnswers: Int
    var percentage: Double {
        guard totalQuestions > 0 else { return 0 }
        return (Double(correctAnswers) / Double(totalQuestions)) * 100
    }
}

// MARK: - Quiz History Models
struct QuizAttempt: Identifiable, Codable {
    let id: UUID
    let date: Date
    let score: Int
    let totalQuestions: Int
    var videoPath: String?

    var percentage: Double {
        guard totalQuestions > 0 else { return 0 }
        return (Double(score) / Double(totalQuestions)) * 100
    }

    init(id: UUID = UUID(), date: Date = Date(), score: Int, totalQuestions: Int, videoPath: String? = nil) {
        self.id = id
        self.date = date
        self.score = score
        self.totalQuestions = totalQuestions
        self.videoPath = videoPath
    }
}

struct SavedQuiz: Identifiable, Codable {
    let id: UUID
    var title: String
    let quizText: String
    let dateCreated: Date
    var attempts: [QuizAttempt]

    init(id: UUID = UUID(), title: String, quizText: String, dateCreated: Date = Date(), attempts: [QuizAttempt] = []) {
        self.id = id
        self.title = title
        self.quizText = quizText
        self.dateCreated = dateCreated
        self.attempts = attempts
    }

    var bestScore: QuizAttempt? {
        attempts.max(by: { $0.percentage < $1.percentage })
    }

    var latestAttempt: QuizAttempt? {
        attempts.max(by: { $0.date < $1.date })
    }
}

class QuizHistoryManager: ObservableObject {
    @Published var savedQuizzes: [SavedQuiz] = []
    private let saveKey = "SavedQuizzes"

    init() {
        loadQuizzes()
    }

    func saveQuiz(_ quiz: SavedQuiz) {
        savedQuizzes.insert(quiz, at: 0) // Add to beginning
        persistQuizzes()
    }

    func addAttempt(to quizID: UUID, attempt: QuizAttempt) {
        if let index = savedQuizzes.firstIndex(where: { $0.id == quizID }) {
            savedQuizzes[index].attempts.append(attempt)
            persistQuizzes()
            print("💾 Added attempt to quiz: \(attempt.score)/\(attempt.totalQuestions)")
        }
    }

    func deleteQuiz(_ quiz: SavedQuiz) {
        savedQuizzes.removeAll { $0.id == quiz.id }
        persistQuizzes()
        print("🗑️ Deleted quiz: \(quiz.title)")
    }

    func renameQuiz(_ quizID: UUID, newTitle: String) {
        if let index = savedQuizzes.firstIndex(where: { $0.id == quizID }) {
            let oldTitle = savedQuizzes[index].title
            savedQuizzes[index].title = newTitle
            persistQuizzes()
            print("✏️ Renamed quiz from '\(oldTitle)' to '\(newTitle)'")
        }
    }

    private func persistQuizzes() {
        if let encoded = try? JSONEncoder().encode(savedQuizzes) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadQuizzes() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([SavedQuiz].self, from: data) {
            savedQuizzes = decoded
        }
    }
}

enum FileType {
    case pdf
    case image
}

struct LoadedFile {
    let title: String
    let text: String
    let type: FileType
}

struct ContentView: View {
    @StateObject private var historyManager = QuizHistoryManager()
    @State private var showPicker = false
    @State private var loadedFiles: [LoadedFile] = []
    @State private var quizText = ""
    @State private var isLoading = false
    @State private var shareURL: IdentifiableURL?
    @State private var questionTypes: [String] = []
    @State private var difficulty: String = "Medium"
    @State private var numQuestions: Double = 10
    @State private var showQuizGame = false
    @State private var showSidebar = false
    @State private var currentQuizID: UUID?
    @State private var showScoreGraph = false
    var body: some View {
        ZStack(alignment: .leading) {
            // Main content
            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 5) {
                            Image("appstore")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 130)
                                .padding(.top, 10)

                            Text("The Quiz Whiz")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                        }

                        Text("Upload PDFs or images and generate a custom quiz!")
                            .font(.headline)
                            .foregroundColor(.gray)
                // Upload button
                Button(action: { showPicker = true }) {
                    Label("Upload Files", systemImage: "plus.rectangle.on.folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                // Show loaded files
                if !loadedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("✅ \(loadedFiles.count) File\(loadedFiles.count == 1 ? "" : "s") Loaded:")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(Array(loadedFiles.enumerated()), id: \.offset) { index, file in
                            HStack {
                                Image(systemName: file.type == .pdf ? "doc.fill" : "photo.fill")
                                    .foregroundColor(file.type == .pdf ? .blue : .green)
                                Text(file.title)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer()

                                Button(action: {
                                    loadedFiles.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                }
                // Question Type
                VStack(alignment: .leading, spacing: 12) {
                    Text("Question Types:")
                        .font(.headline)
                    Toggle("Multiple Choice", isOn: Binding(
                        get: { questionTypes.contains("Multiple Choice") },
                        set: { $0 ? questionTypes.append("Multiple Choice") : questionTypes.removeAll { $0 == "Multiple Choice" } }
                    ))
                    .font(.body)
                    .padding(.vertical, 4)

                    Toggle("True/False", isOn: Binding(
                        get: { questionTypes.contains("True/False") },
                        set: { $0 ? questionTypes.append("True/False") : questionTypes.removeAll { $0 == "True/False" } }
                    ))
                    .font(.body)
                    .padding(.vertical, 4)

                    Toggle("Short Answer", isOn: Binding(
                        get: { questionTypes.contains("Short Answer") },
                        set: { $0 ? questionTypes.append("Short Answer") : questionTypes.removeAll { $0 == "Short Answer" } }
                    ))
                    .font(.body)
                    .padding(.vertical, 4)
                }
                .padding()
                .transformEnvironment(\.font) { $0 = .body }
                // Difficulty
                VStack(alignment: .leading) {
                    Text("Difficulty Level:")
                        .font(.headline)
                    Picker("Difficulty", selection: $difficulty) {
                        Text("Easy").tag("Easy")
                            .font(.body)
                        Text("Medium").tag("Medium")
                            .font(.body)
                        Text("Hard").tag("Hard")
                            .font(.body)
                    }
                    .pickerStyle(.segmented)
                    .scaleEffect(1.1)
                }
                .padding(.horizontal)
                // Number of questions
                VStack(alignment: .leading) {
                    Text("Number of Questions: \(Int(numQuestions))")
                        .font(.headline)
                    Slider(value: $numQuestions, in: 1...50, step: 1)
                }
                .padding(.horizontal)
                // Generate button
                Button(action: generateQuiz) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label("Generate Quiz", systemImage: "sparkles")
                    }
                }
                .disabled(loadedFiles.isEmpty || isLoading)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.top)
                // Output
                if !quizText.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Generated Quiz:")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(quizText)
                            .font(.body)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)

                    }
                    .padding()

                    // Show attempt history if quiz has been played
                    if let quizID = currentQuizID,
                       let currentQuiz = historyManager.savedQuizzes.first(where: { $0.id == quizID }),
                       !currentQuiz.attempts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Your Attempts:")
                                    .font(.title3)
                                    .fontWeight(.semibold)

                                Spacer()

                                if currentQuiz.attempts.count >= 2 {
                                    Button(action: {
                                        withAnimation {
                                            showScoreGraph.toggle()
                                        }
                                    }) {
                                        Label(showScoreGraph ? "Hide Graph" : "View Graph", systemImage: showScoreGraph ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.horizontal)

                            if showScoreGraph && currentQuiz.attempts.count >= 2 {
                                ScoreGraphView(attempts: currentQuiz.attempts.sorted(by: { $0.date < $1.date }))
                                    .frame(height: 250)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                            }

                            VStack(spacing: 8) {
                                ForEach(currentQuiz.attempts.sorted(by: { $0.date > $1.date })) { attempt in
                                    AttemptRowView(attempt: attempt, isBestScore: attempt.id == currentQuiz.bestScore?.id)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }

                    HStack(spacing: 15) {
                        Button(action: {
                            showQuizGame = true
                        }) {
                            Label("Play Quiz", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button(action: {
                            print("🔴🔴🔴 BUTTON PRESSED - Starting PDF generation 🔴🔴🔴")
                            generatePDF()
                        }) {
                            Label("Save PDF", systemImage: "doc.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            }
            .navigationBarHidden(true)
            .background(Color(UIColor.systemGroupedBackground))
            .safeAreaInset(edge: .top) {
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding()
                    }

                    Spacer()

                    Button(action: {
                        startNewQuiz()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .padding()
                    }
                }
                .background(Color(UIColor.systemGroupedBackground).opacity(0.95))
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .sheet(isPresented: $showPicker) {
                DocumentPicker { urls in
                    for url in urls {
                        extractText(from: url)
                    }
                }
            }
            .sheet(item: $shareURL) { identifiableURL in
                let _ = print("📋 ShareSheet showing with URL: \(identifiableURL.url)")
                return ShareSheet(items: [identifiableURL.url])
            }
            .sheet(isPresented: $showQuizGame) {
                QuizGameView(
                    quizText: quizText,
                    historyManager: historyManager,
                    quizID: currentQuizID
                )
            }
            }

            // Overlay to close sidebar when tapping outside
            if showSidebar {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSidebar = false
                        }
                    }
            }

            // Sidebar
            if showSidebar {
                SidebarView(
                    historyManager: historyManager,
                    showSidebar: $showSidebar,
                    onSelectQuiz: { quiz in
                        loadQuiz(quiz)
                    }
                )
                .transition(.move(edge: .leading))
            }
        }
    }
    // MARK: - Generate Quiz (OpenAI)
    func generateQuiz() {
        guard !loadedFiles.isEmpty else { return }
        isLoading = true
        quizText = ""

        // Combine all file texts
        let combinedText = loadedFiles.map { $0.text }.joined(separator: "\n\n")
        let combinedTitle = loadedFiles.count == 1 ? loadedFiles[0].title : "\(loadedFiles.count) Files"

        let joinedTypes = questionTypes.joined(separator: ", ")
        let prompt = """
        You are the Quiz Whiz. Create a \(difficulty) quiz with \(Int(numQuestions)) questions from this document:
        \(combinedText.prefix(4000))
        Question types: \(joinedTypes.isEmpty ? "Any" : joinedTypes).
        Include a final "Answer Key:" section at the end.
        Use no markdown.
        When there are multiple question types, make sure to randomly spread them throughout the quiz.
        """
        Task {
            do {
                // Replace YOUR_API_KEY_HERE
                let apiKey = "API_KEY_HERE")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "model": "gpt-4o",
                    "messages": [["role": "user", "content": prompt]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    await MainActor.run {
                        quizText = content
                        // Save quiz to history
                        let savedQuiz = SavedQuiz(title: combinedTitle, quizText: content)
                        historyManager.saveQuiz(savedQuiz)
                        currentQuizID = savedQuiz.id
                        print("💾 Quiz saved to history with ID: \(savedQuiz.id)")
                    }
                } else {
                    quizText = "⚠️ Failed to parse response."
                }
            } catch {
                quizText = "❌ Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    // MARK: - Quiz Management
    func startNewQuiz() {
        loadedFiles = []
        quizText = ""
        questionTypes = []
        difficulty = "Medium"
        numQuestions = 10
        print("🆕 Started new quiz")
    }

    func loadQuiz(_ quiz: SavedQuiz) {
        quizText = quiz.quizText
        currentQuizID = quiz.id
        showSidebar = false
        print("📂 Loaded quiz: \(quiz.title) with ID: \(quiz.id)")
    }
    // MARK: - Extract Text from Files
    func extractText(from url: URL) {
        let fileExtension = url.pathExtension.lowercased()

        // Determine file type
        if fileExtension == "pdf" {
            extractTextFromPDF(url: url)
        } else if ["jpg", "jpeg", "png", "heic", "heif"].contains(fileExtension) {
            extractTextFromImage(url: url)
        } else {
            print("⚠️ Unsupported file type: \(fileExtension)")
        }
    }

    // MARK: - Extract PDF Text
    func extractTextFromPDF(url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            var extracted = ""
            var resolvedTitle: String? = nil
            // Try loading from data first
            if let data = try? Data(contentsOf: url), let pdf = PDFDocument(data: data) {
                if let attrs = pdf.documentAttributes,
                   let metaTitle = attrs[PDFDocumentAttribute.titleAttribute] as? String,
                   !metaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolvedTitle = metaTitle
                }
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i) {
                        extracted += page.string ?? ""
                    }
                }
            } else if let pdf = PDFDocument(url: url) { // fallback
                if let attrs = pdf.documentAttributes,
                   let metaTitle = attrs[PDFDocumentAttribute.titleAttribute] as? String,
                   !metaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolvedTitle = metaTitle
                }
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i) {
                        extracted += page.string ?? ""
                    }
                }
            }
            // Final fallback to filename if no metadata title
            let fileName = url.deletingPathExtension().lastPathComponent
            let titleToUse = (resolvedTitle?.isEmpty == false) ? resolvedTitle! : fileName
            DispatchQueue.main.async {
                let loadedFile = LoadedFile(title: titleToUse, text: extracted, type: .pdf)
                self.loadedFiles.append(loadedFile)
                print("📄 Added PDF: \(titleToUse)")
            }
        }
    }

    // MARK: - Extract Text from Image using OCR
    func extractTextFromImage(url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = UIImage(contentsOfFile: url.path),
                  let cgImage = image.cgImage else {
                print("❌ Failed to load image from: \(url.path)")
                return
            }

            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNRecognizeTextRequest { (request, error) in
                if let error = error {
                    print("❌ OCR Error: \(error.localizedDescription)")
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    print("⚠️ No text found in image")
                    return
                }

                let extractedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                let fileName = url.deletingPathExtension().lastPathComponent

                DispatchQueue.main.async {
                    let loadedFile = LoadedFile(title: fileName, text: extractedText, type: .image)
                    self.loadedFiles.append(loadedFile)
                    print("🖼️ Added Image with OCR: \(fileName) (\(extractedText.count) characters)")
                }
            }

            // Set recognition level to accurate for better results
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            do {
                try requestHandler.perform([request])
            } catch {
                print("❌ Failed to perform OCR: \(error.localizedDescription)")
            }
        }
    }
    // MARK: - Generate PDF (Paginated with Core Text)
    func generatePDF() {
        guard !quizText.isEmpty else {
            print("⚠️ Quiz text is empty")
            return
        }

        // Use Documents directory for better persistence
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Could not access Documents directory")
            return
        }

        // Generate title from loaded files
        let pdfTitle = loadedFiles.count == 1 ? loadedFiles[0].title : (loadedFiles.isEmpty ? "Quiz" : "\(loadedFiles.count)_Files")

        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "Quiz_\(pdfTitle.replacingOccurrences(of: " ", with: "_"))_\(timestamp).pdf"
        let fileURL = documentsPath.appendingPathComponent(fileName)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: fileURL)

        print("📝 Generating PDF at: \(fileURL.path)")

        // PDF page setup
        let pageWidth: CGFloat = 8.5 * 72.0
        let pageHeight: CGFloat = 11 * 72.0
        let margin: CGFloat = 40
        let printableRect = CGRect(x: margin, y: margin, width: pageWidth - margin*2, height: pageHeight - margin*2)

        let pdfMetaData = [
            kCGPDFContextCreator: "The Quiz Whiz",
            kCGPDFContextAuthor: "Leona",
            kCGPDFContextTitle: pdfTitle
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), format: format)

        do {
            try renderer.writePDF(to: fileURL, withActions: { context in
                // Split quiz into questions and answer key
                let lines = quizText.components(separatedBy: .newlines)
                var questions: [String] = []
                var currentQuestion = ""
                var answerKeyIndex: Int?
                var isInAnswerKey = false

                for (index, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)

                    // Check if this is the answer key section
                    if trimmed.range(of: #"^Answer\s+Key:?"#, options: [.regularExpression, .caseInsensitive]) != nil {
                        // Save current question before answer key
                        if !currentQuestion.isEmpty {
                            questions.append(currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        answerKeyIndex = questions.count
                        currentQuestion = line + "\n"
                        isInAnswerKey = true
                        continue
                    }

                    // Check if line starts with a number followed by a period or closing paren
                    let isQuestionStart = trimmed.range(of: #"^\d+[\.)]\s"#, options: .regularExpression) != nil

                    if isQuestionStart && !currentQuestion.isEmpty && !isInAnswerKey {
                        questions.append(currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentQuestion = line + "\n"
                    } else {
                        currentQuestion += line + "\n"
                    }
                }

                // Add the last question or answer key section
                if !currentQuestion.isEmpty {
                    questions.append(currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                // If no questions were parsed, fall back to the full text
                if questions.isEmpty {
                    questions = [quizText]
                }

                print("📝 Parsed \(questions.count) sections from quiz")
                if let akIndex = answerKeyIndex {
                    print("🔑 Answer key starts at section \(akIndex + 1)")
                }

                // Debug: print first line of each section
                for (idx, q) in questions.enumerated() {
                    let firstLine = q.components(separatedBy: .newlines).first ?? ""
                    print("  Section \(idx + 1): \(firstLine.prefix(50))...")
                }

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byWordWrapping
                paragraphStyle.alignment = .left

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .paragraphStyle: paragraphStyle
                ]

                var currentY: CGFloat = margin
                var questionIndex = 0
                var needsNewPage = true
                var cgContext: CGContext?

                while questionIndex < questions.count {
                    // Force new page for answer key
                    if let akIndex = answerKeyIndex, questionIndex == akIndex {
                        print("📄 Starting answer key on new page")
                        needsNewPage = true
                    }

                    if needsNewPage {
                        context.beginPage()
                        currentY = margin
                        needsNewPage = false
                        print("📄 New page started, currentY reset to \(currentY)")
                    }

                    let questionText = questions[questionIndex]
                    let attributedText = NSAttributedString(string: questionText, attributes: attributes)

                    // Calculate height needed for this question
                    let boundingSize = CGSize(width: printableRect.width, height: CGFloat.greatestFiniteMagnitude)
                    let questionHeight = ceil(attributedText.boundingRect(
                        with: boundingSize,
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    ).height)

                    let spaceRemaining = (margin + printableRect.height) - currentY

                    print("  Q\(questionIndex + 1): height=\(questionHeight), currentY=\(currentY), spaceRemaining=\(spaceRemaining)")

                    // If question doesn't fit, start new page
                    if questionHeight > spaceRemaining && currentY > margin {
                        print("  ↪️ Moving to new page")
                        needsNewPage = true
                        continue // Don't increment questionIndex, try again on new page
                    }

                    // Draw the question using NSAttributedString (works with UIKit coordinates)
                    let drawRect = CGRect(x: margin, y: currentY, width: printableRect.width, height: questionHeight)
                    attributedText.draw(in: drawRect)

                    print("  ✅ Drew Q\(questionIndex + 1) at y=\(currentY), height=\(questionHeight)")

                    // Move Y position down
                    currentY += questionHeight + 15 // Add spacing between questions
                    questionIndex += 1
                }
            })

            // Verify the file exists and has content
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                print("✅ PDF created successfully")
                print("📄 File size: \(fileSize) bytes")
                print("📍 Location: \(fileURL.path)")

                if fileSize == 0 {
                    print("⚠️ Warning: PDF file is empty!")
                }

                // Store the URL and show share sheet on main thread
                DispatchQueue.main.async {
                    print("🔗 Setting shareURL to: \(fileURL)")
                    self.shareURL = IdentifiableURL(url: fileURL)
                    print("✅ shareURL is now: \(String(describing: self.shareURL?.url))")
                }
            } else {
                print("❌ PDF file was not created")
            }

        } catch {
            print("❌ Failed to generate PDF: \(error.localizedDescription)")
        }
    }
}
// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf, UTType.image, UTType.jpeg, UTType.png, UTType.heic])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.modalPresentationStyle = .formSheet
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            controller.dismiss(animated: true)

            var copiedURLs: [URL] = []

            for sourceURL in urls {
                let needsStop = sourceURL.startAccessingSecurityScopedResource()
                defer { if needsStop { sourceURL.stopAccessingSecurityScopedResource() } }

                // Create a temp destination URL inside the app sandbox
                let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(sourceURL.lastPathComponent)
                // Remove existing file at destination if present
                try? FileManager.default.removeItem(at: destinationURL)
                do {
                    // Copy the picked file into our sandbox
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    copiedURLs.append(destinationURL)
                } catch {
                    print("Failed to copy picked file: \(error)")
                    copiedURLs.append(sourceURL) // Fallback to original URL
                }
            }

            DispatchQueue.main.async {
                self.parent.onPick(copiedURLs)
            }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        print("🎬 ShareSheet makeUIViewController called")
        print("📦 Items count: \(items.count)")
        for (index, item) in items.enumerated() {
            print("  Item \(index): \(type(of: item)) = \(item)")
        }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        print("✅ UIActivityViewController created")
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Quiz Game View
struct QuizGameView: View {
    let quizText: String
    @ObservedObject var historyManager: QuizHistoryManager
    let quizID: UUID?
    @Environment(\.dismiss) var dismiss

    @State private var questions: [QuizQuestion] = []
    @State private var currentQuestionIndex = 0
    @State private var userAnswers: [Int: String] = [:]
    @State private var showResults = false
    @State private var quizResult: QuizResult?
    @State private var isRecording = false
    @State private var recordingURL: URL?
    @State private var recordingError: String?
    @State private var videoWriter: AVAssetWriter?
    @State private var videoWriterInput: AVAssetWriterInput?
    private let recorder = RPScreenRecorder.shared()

    var body: some View {
        NavigationView {
            VStack {
                if questions.isEmpty {
                    Text("No questions found in quiz")
                        .foregroundColor(.gray)
                } else if showResults, let result = quizResult {
                    // Results view
                    resultsView(result: result)
                } else {
                    // Quiz view
                    quizView
                }
            }
            .navigationTitle("Quiz Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isRecording {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Recording")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .onAppear {
                parseQuiz()
                startRecording()
            }
        }
    }

    var quizView: some View {
        VStack(spacing: 20) {
            // Recording error banner
            if let error = recordingError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Progress
            HStack {
                Text("Question \(currentQuestionIndex + 1) of \(questions.count)")
                    .font(.headline)
                Spacer()
                Text("\(userAnswers.count)/\(questions.count) answered")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)

            ScrollView {
                if currentQuestionIndex < questions.count {
                    let question = questions[currentQuestionIndex]

                    VStack(alignment: .leading, spacing: 20) {
                        // Question text
                        Text(question.question)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)

                        // Answer options based on type
                        switch question.type {
                        case .multipleChoice, .trueFalse:
                            let displayOptions = question.type == .trueFalse ? ["True", "False"] : question.options

                            ForEach(displayOptions, id: \.self) { displayOption in
                                let isSelected = userAnswers[question.number]?.lowercased() == displayOption.lowercased()

                                Button(action: {
                                    userAnswers[question.number] = displayOption
                                }) {
                                    HStack {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isSelected ? .blue : .gray)
                                        Text(displayOption)
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
                                    .cornerRadius(10)
                                }
                            }

                        case .shortAnswer:
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your Answer:")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)

                                TextEditor(text: Binding(
                                    get: { userAnswers[question.number] ?? "" },
                                    set: { userAnswers[question.number] = $0 }
                                ))
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            }

            // Navigation buttons
            HStack(spacing: 15) {
                if currentQuestionIndex > 0 {
                    Button(action: {
                        currentQuestionIndex -= 1
                    }) {
                        Label("Previous", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if currentQuestionIndex < questions.count - 1 {
                    Button(action: {
                        currentQuestionIndex += 1
                    }) {
                        Label("Next", systemImage: "chevron.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: {
                        checkAnswers()
                    }) {
                        Label("Submit Quiz", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .padding()
        }
    }

    func resultsView(result: QuizResult) -> some View {
        VStack(spacing: 30) {
            Image(systemName: result.percentage >= 70 ? "star.fill" : "star")
                .font(.system(size: 80))
                .foregroundColor(result.percentage >= 70 ? .yellow : .gray)

            Text("Quiz Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 10) {
                Text("\(result.correctAnswers) / \(result.totalQuestions)")
                    .font(.system(size: 60, weight: .bold))

                Text("\(Int(result.percentage))%")
                    .font(.title)
                    .foregroundColor(.gray)
            }

            if result.percentage >= 90 {
                Text("Excellent! 🎉")
                    .font(.title2)
                    .foregroundColor(.green)
            } else if result.percentage >= 70 {
                Text("Good job! 👍")
                    .font(.title2)
                    .foregroundColor(.blue)
            } else {
                Text("Keep practicing! 💪")
                    .font(.title2)
                    .foregroundColor(.orange)
            }

            Spacer()

            HStack(spacing: 15) {
                Button(action: {
                    // Reset and play again
                    userAnswers.removeAll()
                    currentQuestionIndex = 0
                    showResults = false
                }) {
                    Label("Play Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    dismiss()
                }) {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .padding()
    }

    func parseQuiz() {
        print("🎮 Parsing quiz for game...")

        let lines = quizText.components(separatedBy: .newlines)
        var parsedQuestions: [QuizQuestion] = []
        var answerKey: [Int: String] = [:]
        var isInAnswerKey = false

        var currentQuestion: String = ""
        var currentNumber: Int = 0
        var currentOptions: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for answer key
            if trimmed.range(of: #"^Answer\s+Key:?"#, options: [.regularExpression, .caseInsensitive]) != nil {
                isInAnswerKey = true
                // Save any pending question
                if !currentQuestion.isEmpty && currentNumber > 0 {
                    let type = determineQuestionType(question: currentQuestion, options: currentOptions)
                    parsedQuestions.append(QuizQuestion(
                        number: currentNumber,
                        question: currentQuestion,
                        type: type,
                        options: currentOptions,
                        correctAnswer: "" // Will be filled from answer key
                    ))
                }
                continue
            }

            // Parse answer key
            if isInAnswerKey {
                // Look for patterns like "1. A" or "1) Answer text"
                if let colonIndex = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }) {
                    let numStr = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let num = Int(numStr), colonIndex < trimmed.endIndex {
                        let answerStart = trimmed.index(after: colonIndex)
                        var answerStr = String(trimmed[answerStart...]).trimmingCharacters(in: .whitespaces)

                        // Strip letter prefix if present (e.g., "c) Cheetah" -> "Cheetah")
                        if let prefixMatch = answerStr.range(of: #"^[a-dA-D][\.)]\s+"#, options: .regularExpression) {
                            answerStr = String(answerStr[prefixMatch.upperBound...])
                        }

                        if !answerStr.isEmpty {
                            answerKey[num] = answerStr
                            print("  Answer key: Q\(num) = '\(answerStr)'")
                        }
                    }
                }
                continue
            }

            // Check if line starts with a question number
            if let match = trimmed.range(of: #"^(\d+)[\.)]\s+"#, options: .regularExpression) {
                // Save previous question
                if !currentQuestion.isEmpty && currentNumber > 0 {
                    let type = determineQuestionType(question: currentQuestion, options: currentOptions)
                    parsedQuestions.append(QuizQuestion(
                        number: currentNumber,
                        question: currentQuestion,
                        type: type,
                        options: currentOptions,
                        correctAnswer: ""
                    ))
                }

                // Start new question
                let numEndIndex = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }) ?? trimmed.startIndex
                let numStr = trimmed[..<numEndIndex]
                currentNumber = Int(numStr) ?? 0
                let questionStart = trimmed.index(after: numEndIndex)
                currentQuestion = String(trimmed[questionStart...]).trimmingCharacters(in: .whitespaces)
                currentOptions = []
            }
            // Check for answer options (a), b), A), etc.)
            else if trimmed.range(of: #"^[a-dA-D][\.)]\s+"#, options: .regularExpression) != nil {
                if let parenIndex = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }) {
                    let optionText = String(trimmed[trimmed.index(after: parenIndex)...]).trimmingCharacters(in: .whitespaces)
                    currentOptions.append(optionText)
                }
            }
            // Continue current question
            else if !trimmed.isEmpty && !isInAnswerKey {
                currentQuestion += " " + trimmed
            }
        }

        // Save last question
        if !currentQuestion.isEmpty && currentNumber > 0 {
            let type = determineQuestionType(question: currentQuestion, options: currentOptions)
            parsedQuestions.append(QuizQuestion(
                number: currentNumber,
                question: currentQuestion,
                type: type,
                options: currentOptions,
                correctAnswer: ""
            ))
        }

        // Fill in correct answers from answer key and filter out invalid/duplicate questions
        var seenNumbers = Set<Int>()
        questions = parsedQuestions.compactMap { q in
            // Skip questions with no number or empty question text
            guard q.number > 0, !q.question.isEmpty else {
                print("⚠️ Skipping invalid question: number=\(q.number), text='\(q.question.prefix(50))'")
                return nil
            }

            // Skip duplicate question numbers
            guard !seenNumbers.contains(q.number) else {
                print("⚠️ Skipping duplicate question number: \(q.number)")
                return nil
            }

            seenNumbers.insert(q.number)

            return QuizQuestion(
                number: q.number,
                question: q.question,
                type: q.type,
                options: q.options,
                correctAnswer: answerKey[q.number] ?? ""
            )
        }

        print("🎮 Parsed \(questions.count) questions")
        for q in questions {
            print("  Q\(q.number): \(q.type) - '\(q.question.prefix(50))...'")
            print("    Options: \(q.options)")
            print("    Answer: '\(q.correctAnswer)'")
        }
    }

    func determineQuestionType(question: String, options: [String]) -> QuestionType {
        let lowerQuestion = question.lowercased()

        // Check for True/False
        let hasTrueFalseInQuestion = lowerQuestion.contains("true or false") ||
        lowerQuestion.contains("(t/f)") ||
        lowerQuestion.contains("true/false")

        let hasTrueFalseOptions = options.count == 2 &&
        options.contains(where: { $0.lowercased().contains("true") }) &&
        options.contains(where: { $0.lowercased().contains("false") })

        if hasTrueFalseInQuestion || hasTrueFalseOptions {
            print("    Detected True/False question")
            return .trueFalse
        }

        // Check for multiple choice (has options)
        if options.count > 0 {
            return .multipleChoice
        }

        // Default to short answer
        return .shortAnswer
    }

    func checkAnswers() {
        var correctCount = 0

        print("🔍 Checking answers...")
        for question in questions {
            if let userAnswer = userAnswers[question.number] {
                var cleanUserAnswer = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                var cleanCorrectAnswer = question.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                print("  Q\(question.number): Type=\(question.type)")
                print("    User: '\(cleanUserAnswer)'")
                print("    Correct: '\(cleanCorrectAnswer)'")

                var isCorrect = false

                // For True/False, be flexible with matching
                if question.type == .trueFalse {
                    // Normalize variations of true/false
                    if cleanUserAnswer.contains("true") || cleanUserAnswer == "t" {
                        cleanUserAnswer = "true"
                    } else if cleanUserAnswer.contains("false") || cleanUserAnswer == "f" {
                        cleanUserAnswer = "false"
                    }

                    if cleanCorrectAnswer.contains("true") || cleanCorrectAnswer == "t" {
                        cleanCorrectAnswer = "true"
                    } else if cleanCorrectAnswer.contains("false") || cleanCorrectAnswer == "f" {
                        cleanCorrectAnswer = "false"
                    }

                    isCorrect = cleanUserAnswer == cleanCorrectAnswer
                }
                // For Multiple Choice, handle letter-based answers (A, B, C, D)
                else if question.type == .multipleChoice {
                    // Check if answer key is just a letter
                    if cleanCorrectAnswer.count == 1 && "abcd".contains(cleanCorrectAnswer) {
                        // Convert letter to option index (a=0, b=1, etc.)
                        let letterIndex = cleanCorrectAnswer.first!.asciiValue! - Character("a").asciiValue!
                        let correctOptionIndex = Int(letterIndex)

                        if correctOptionIndex < question.options.count {
                            let correctOptionText = question.options[correctOptionIndex].lowercased()
                            isCorrect = cleanUserAnswer == correctOptionText
                            print("    Letter '\(cleanCorrectAnswer)' maps to option: '\(correctOptionText)'")
                        }
                    } else {
                        // Direct text comparison
                        isCorrect = cleanUserAnswer == cleanCorrectAnswer
                    }
                }
                // For Short Answer
                else {
                    isCorrect = cleanUserAnswer == cleanCorrectAnswer
                }

                if isCorrect {
                    correctCount += 1
                    print("    ✅ CORRECT")
                } else {
                    print("    ❌ WRONG")
                }
            } else {
                print("  Q\(question.number): Not answered")
            }
        }

        quizResult = QuizResult(totalQuestions: questions.count, correctAnswers: correctCount)
        showResults = true

        print("🎯 Quiz results: \(correctCount)/\(questions.count) = \(quizResult?.percentage ?? 0)%")

        // Stop recording and save attempt
        stopRecording { videoPath in
            if let quizID = quizID {
                let attempt = QuizAttempt(score: correctCount, totalQuestions: questions.count, videoPath: videoPath)
                historyManager.addAttempt(to: quizID, attempt: attempt)
                print("💾 Saved quiz attempt: \(correctCount)/\(questions.count)")
                if let path = videoPath {
                    print("🎥 Video saved at: \(path)")
                }
            } else {
                print("⚠️ Could not save attempt: quiz ID is nil")
            }
        }
    }

    func startRecording() {
        guard recorder.isAvailable else {
            let errorMsg = "Recording not available (requires real device)"
            print("⚠️ \(errorMsg)")
            recordingError = errorMsg
            isRecording = false
            return
        }

        guard !recorder.isRecording else {
            print("⚠️ Already recording")
            return
        }

        print("🎥 Attempting to start recording...")
        print("🎥 Recorder available: \(recorder.isAvailable)")

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videoFileName = "quiz_\(UUID().uuidString).mp4"
        let videoURL = documentsPath.appendingPathComponent(videoFileName)

        // Set up video writer
        do {
            let assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)

            // Get actual screen dimensions
            let screenSize = UIScreen.main.bounds.size
            let scale = UIScreen.main.scale
            let width = Int(screenSize.width * scale)
            let height = Int(screenSize.height * scale)

            print("📱 Screen dimensions: \(width)x\(height) (scale: \(scale))")

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]

            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = true

            if assetWriter.canAdd(writerInput) {
                assetWriter.add(writerInput)
            }

            videoWriter = assetWriter
            videoWriterInput = writerInput
            recordingURL = videoURL

            print("✅ Video writer set up at: \(videoURL.path)")

        } catch {
            print("❌ Failed to create video writer: \(error.localizedDescription)")
            recordingError = "Failed to create video writer"
            return
        }

        // Start capturing with ReplayKit
        recorder.startCapture(handler: { (sampleBuffer, bufferType, error) in
            if let error = error {
                print("❌ Capture error: \(error.localizedDescription)")
                return
            }

            guard bufferType == .video else { return }

            // Write video frames
            if let writer = self.videoWriter, let input = self.videoWriterInput {
                if writer.status == .unknown {
                    writer.startWriting()
                    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    print("🎬 Started writing video")
                }

                if writer.status == .writing && input.isReadyForMoreMediaData {
                    input.append(sampleBuffer)
                }
            }

        }, completionHandler: { error in
            DispatchQueue.main.async {
                if let error = error {
                    let errorMsg = "Failed to start recording: \(error.localizedDescription)"
                    print("❌ \(errorMsg)")
                    self.recordingError = errorMsg
                    self.isRecording = false
                } else {
                    print("✅ Recording started successfully!")
                    self.isRecording = true
                    self.recordingError = nil
                }
            }
        })
    }

    func stopRecording(completion: @escaping (String?) -> Void) {
        print("🛑 Attempting to stop recording...")

        guard isRecording else {
            print("⚠️ Not currently recording, skipping save")
            completion(nil)
            return
        }

        // Stop capturing
        recorder.stopCapture { error in
            if let error = error {
                print("❌ Failed to stop capture: \(error.localizedDescription)")
            } else {
                print("✅ Capture stopped successfully")
            }
        }

        DispatchQueue.main.async {
            self.isRecording = false
        }

        // Finalize video file
        guard let writer = videoWriter, let input = videoWriterInput else {
            print("⚠️ No video writer available")
            completion(nil)
            return
        }

        input.markAsFinished()

        writer.finishWriting {
            if writer.status == .completed {
                if let url = self.recordingURL {
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    print("✅ Video saved successfully!")
                    print("📹 Path: \(url.path)")
                    print("📦 File size: \(fileSize / 1024 / 1024)MB")

                    // Return just the filename
                    completion(url.lastPathComponent)
                } else {
                    print("❌ No recording URL available")
                    completion(nil)
                }
            } else {
                print("❌ Video writer failed: \(writer.status.rawValue)")
                if let error = writer.error {
                    print("❌ Error: \(error.localizedDescription)")
                }
                completion(nil)
            }

            // Clean up
            self.videoWriter = nil
            self.videoWriterInput = nil
            self.recordingURL = nil
        }
    }
}

// MARK: - Score Graph View
struct ScoreGraphView: View {
    let attempts: [QuizAttempt]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Score History")
                .font(.headline)
                .foregroundColor(.secondary)

            Chart(attempts) { attempt in
                LineMark(
                    x: .value("Attempt", formatAttemptNumber(attempt)),
                    y: .value("Score", attempt.percentage)
                )
                .foregroundStyle(Color.blue)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Attempt", formatAttemptNumber(attempt)),
                    y: .value("Score", attempt.percentage)
                )
                .foregroundStyle(Color.blue)
                .symbolSize(100)

                AreaMark(
                    x: .value("Attempt", formatAttemptNumber(attempt)),
                    y: .value("Score", attempt.percentage)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let intValue = value.as(Double.self) {
                            Text("\(Int(intValue))%")
                                .font(.caption)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let stringValue = value.as(String.self) {
                            Text(stringValue)
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 200)

            HStack {
                Label("Average: \(Int(averageScore))%", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundColor(.blue)

                Spacer()

                if let trend = scoreTrend {
                    Label(trend, systemImage: trendIcon)
                        .font(.caption)
                        .foregroundColor(trendColor)
                }
            }
        }
    }

    func formatAttemptNumber(_ attempt: QuizAttempt) -> String {
        if let index = attempts.firstIndex(where: { $0.id == attempt.id }) {
            return "#\(index + 1)"
        }
        return ""
    }

    var averageScore: Double {
        guard !attempts.isEmpty else { return 0 }
        let total = attempts.reduce(0.0) { $0 + $1.percentage }
        return total / Double(attempts.count)
    }

    var scoreTrend: String? {
        guard attempts.count >= 2 else { return nil }
        let last3 = Array(attempts.suffix(3))
        guard last3.count >= 2 else { return nil }

        let firstAvg = last3[0].percentage
        let lastAvg = last3[last3.count - 1].percentage

        let difference = lastAvg - firstAvg

        if difference > 5 {
            return "Improving"
        } else if difference < -5 {
            return "Declining"
        } else {
            return "Stable"
        }
    }

    var trendIcon: String {
        guard let trend = scoreTrend else { return "minus" }
        switch trend {
        case "Improving": return "arrow.up.right"
        case "Declining": return "arrow.down.right"
        default: return "minus"
        }
    }

    var trendColor: Color {
        guard let trend = scoreTrend else { return .gray }
        switch trend {
        case "Improving": return .green
        case "Declining": return .orange
        default: return .gray
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @ObservedObject var historyManager: QuizHistoryManager
    @Binding var showSidebar: Bool
    let onSelectQuiz: (SavedQuiz) -> Void

    @State private var showRenameAlert = false
    @State private var quizToRename: SavedQuiz?
    @State private var newQuizName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Quiz History")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSidebar = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color(UIColor.systemGroupedBackground))

            Divider()

            // Quiz list
            if historyManager.savedQuizzes.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "tray")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No saved quizzes yet")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("Generate a quiz to see it here!")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(historyManager.savedQuizzes) { quiz in
                            Button(action: {
                                onSelectQuiz(quiz)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(quiz.title)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        HStack(spacing: 8) {
                                            Text(quiz.dateCreated, style: .date)
                                                .font(.caption)
                                                .foregroundColor(.gray)

                                            if let latestAttempt = quiz.latestAttempt {
                                                Text("•")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                Text("Latest: \(latestAttempt.score)/\(latestAttempt.totalQuestions) (\(Int(latestAttempt.percentage))%)")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                        }

                                        if let bestScore = quiz.bestScore, quiz.attempts.count > 1 {
                                            Text("Best: \(bestScore.score)/\(bestScore.totalQuestions) (\(Int(bestScore.percentage))%)")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    Spacer()

                                    VStack(spacing: 4) {
                                        if !quiz.attempts.isEmpty {
                                            Text("\(quiz.attempts.count)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .frame(minWidth: 20, minHeight: 20)
                                                .background(Color.orange)
                                                .clipShape(Circle())
                                            Text("attempts")
                                                .font(.system(size: 9))
                                                .foregroundColor(.gray)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .background(Color(UIColor.systemBackground))
                            }
                            .contextMenu {
                                Button(action: {
                                    quizToRename = quiz
                                    newQuizName = quiz.title
                                    showRenameAlert = true
                                }) {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive, action: {
                                    historyManager.deleteQuiz(quiz)
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive, action: {
                                    historyManager.deleteQuiz(quiz)
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button(action: {
                                    quizToRename = quiz
                                    newQuizName = quiz.title
                                    showRenameAlert = true
                                }) {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }

                            Divider()
                                .padding(.leading)
                        }
                    }
                }
            }
        }
        .frame(width: UIScreen.main.bounds.width * 0.75)
        .background(Color(UIColor.systemBackground))
        .shadow(radius: 5)
        .alert("Rename Quiz", isPresented: $showRenameAlert) {
            TextField("Quiz Name", text: $newQuizName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if let quiz = quizToRename, !newQuizName.trimmingCharacters(in: .whitespaces).isEmpty {
                    historyManager.renameQuiz(quiz.id, newTitle: newQuizName)
                }
            }
        } message: {
            Text("Enter a new name for the quiz")
        }
    }
}

// MARK: - Attempt Row View
struct AttemptRowView: View {
    let attempt: QuizAttempt
    let isBestScore: Bool
    @State private var showVideoPlayer = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(attempt.score)/\(attempt.totalQuestions)")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(Int(attempt.percentage))%")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            attempt.percentage >= 90 ? Color.green :
                            attempt.percentage >= 70 ? Color.blue :
                            Color.orange
                        )
                        .cornerRadius(4)
                }

                Text(attempt.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(attempt.date, style: .time)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: {
                    if attempt.videoPath != nil {
                        showVideoPlayer = true
                    }
                }) {
                    Image(systemName: attempt.videoPath != nil ? "play.circle.fill" : "video.slash")
                        .font(.title2)
                        .foregroundColor(attempt.videoPath != nil ? .blue : .gray)
                }
                .disabled(attempt.videoPath == nil)

                if isBestScore {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .sheet(isPresented: $showVideoPlayer) {
            if let videoPath = attempt.videoPath {
                VideoPlayerView(videoFileName: videoPath)
            }
        }
    }
}

// MARK: - Video Player View
struct VideoPlayerView: View {
    let videoFileName: String
    @Environment(\.dismiss) var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationView {
            VStack {
                if let videoURL = getVideoURL() {
                    VideoPlayer(player: player ?? AVPlayer(url: videoURL))
                        .onAppear {
                            player = AVPlayer(url: videoURL)
                            player?.play()
                        }
                        .onDisappear {
                            player?.pause()
                            player = nil
                        }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        Text("Video not found")
                            .font(.headline)
                        Text("The recording may have been deleted")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                }
            }
            .navigationTitle("Quiz Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    func getVideoURL() -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videoURL = documentsPath.appendingPathComponent(videoFileName)

        if FileManager.default.fileExists(atPath: videoURL.path) {
            return videoURL
        }
        return nil
    }
}

