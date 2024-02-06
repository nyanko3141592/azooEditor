//
//  ContentView.swift
//  azooKeyTmp
//
//  Created by Naoki Takahashi on 2024/02/04.
//

import SwiftUI
import RealityKit
import WrappingHStack
import KanaKanjiConverterModule

@MainActor
struct ContentView: View {
    @State private var composingText = ComposingText()
    @State private var result = ""
    @State private var converter = KanaKanjiConverter()
    @State private var candidates: [Candidate] = []
    @State private var selection: Int? = nil
    @State private var candidateCount = 5
    @State private var imeState = true
    @State private var deleteTask: Task<Void, any Error>?
    @State private var justCopied: Bool = false
    @FocusState private var textFieldFocus
    private static let option = ConvertRequestOptions(
        requireJapanesePrediction: false,
        requireEnglishPrediction: false,
        keyboardLanguage: .ja_JP,
        learningType: .inputAndOutput,
        dictionaryResourceURL: Bundle.main.bundleURL.appending(path: "Dictionary", directoryHint: .isDirectory),
        memoryDirectoryURL: .documentsDirectory,
        sharedContainerURL: .applicationDirectory,
        metadata: .init(appVersionString: "azooEditor Version 1.0")
    )

    func commitIndex(_ index: Int?) {
        defer {
            self.selection = nil
            self.candidateCount = 5
        }
        if let index {
            guard index < self.candidates.endIndex else {
                return
            }
            let candidate = self.candidates[index]
            self.result += candidate.text
            self.composingText.prefixComplete(correspondingCount: candidate.correspondingCount)
            self.converter.setCompletedData(candidate)
            self.converter.updateLearningData(candidate)
            if !composingText.isEmpty {
                self.updateCandidates()
            } else {
                self.composingText = ComposingText()
                self.candidates = []
                self.converter.stopComposition()
            }
        } else {
            result += composingText.convertTarget
            self.composingText = ComposingText()
            self.candidates = []
        }
    }

    @ViewBuilder private var candidatesView: some View {
        ForEach(candidates.indices.prefix(candidateCount), id: \.self) { index in
            Button {
                commitIndex(index)
            } label: {
                Text(candidates[index].text)
                    .font(.largeTitle)
                    .bold(selection == index)
                    .underline(selection == index)
                    .padding()
            }
        }
        if candidates.count > candidateCount {
            Button("More", systemImage: "plus") {
                candidateCount = 1000
            }
        }
    }

    private func updateCandidates() {
        let results = converter.requestCandidates(self.composingText, options: Self.option)
        self.candidates = results.mainResults
    }

    private func nextCandidate() {
        if let currentSelection = selection {
            let newSelection = min(currentSelection + 1, candidates.count)
            if newSelection + 1 > candidateCount {
                candidateCount += 5
            }
            self.selection = newSelection
        } else {
            self.updateCandidates()
            self.selection = 0
        }
    }

    private func triggerReturn() {
        if self.composingText.isEmpty {
            self.result += "\n"
        } else {
            self.commitIndex(selection)
        }
    }

    private func triggerSpace() {
        if composingText.isEmpty {
            result += " "
        } else {
            nextCandidate()
        }
    }

    private func triggerDelete() {
        if self.composingText.isEmpty {
            _ = self.result.popLast()
        } else {
            self.composingText.deleteBackwardFromCursorPosition(count: 1)
            self.candidates = []
            self.selection = nil
        }
    }

    private func clear() {
        result = ""
        candidates = []
        composingText = ComposingText()
        selection = nil
    }

    private func copy() {
        UIPasteboard.general.string = self.result
        Task {
            if self.justCopied {
                return
            }
            self.justCopied = true
            try await Task.sleep(for: .seconds(1))
            self.justCopied = false
        }
    }

    private var textViewCommand: TextViewCommands {
        .init(
            cut: {
                self.copy()
                self.clear()
            },
            copy: {
                self.copy()
            }
        )
    }

    var body: some View {
        HStack{
            VStack {
                Text("azooEditor")
                    .font(.extraLargeTitle2)
                    .background {
                        // Here's some hacky impl to get keyboard event correctly
                        // delete from virtual keyboard in visionOS cannot be captured `onKeyPress`
                        // to capture it, get method here always return 'a' and if the newValue is "" delete is fired.
                        CommandOverrideTextView(text: .init(get: { "a" }, set: { newValue in
                            if newValue.count == 1 {
                                // empty
                                return
                            }
                            if newValue.isEmpty {
                                self.triggerDelete()
                                return
                            }
                            let key = newValue.last!
                            if imeState == false {
                                self.result.append(key)
                                return
                            }
                            if key == "\n" {
                                self.triggerReturn()
                                return
                            }
                            if key == " " {
                                self.triggerSpace()
                                return
                            }
                            let target = [
                                ".": "。",
                                ",": "、",
                                "-": "ー",
                                "!": "！",
                                "?": "？",
                            ][key, default: key]
                            self.composingText.insertAtCursorPosition(target.lowercased(), inputStyle: .roman2kana)
                        }), TextViewCommands: textViewCommand)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(maxWidth: 1, maxHeight: 1)
                            .focused($textFieldFocus)
                            .onKeyPress(.return) {
                                self.triggerReturn()
                                return .handled
                            }
                            .onKeyPress(.delete, phases: .down) { _ in
                                self.triggerDelete()
                                self.deleteTask?.cancel()
                                self.deleteTask = Task {
                                    // Wait for 0.4s first
                                    try await Task.sleep(for: .milliseconds(400))
                                    while !Task.isCancelled {
                                        self.triggerDelete()
                                        // then trigger for every 0.1s
                                        try await Task.sleep(for: .milliseconds(100))
                                    }
                                }
                                return .handled
                            }
                            .onKeyPress(.delete, phases: .up) { _ in
                                self.deleteTask?.cancel()
                                return .handled
                            }
                            .onKeyPress(.clear) {
                                self.triggerDelete()
                                return .handled
                            }
                            .onKeyPress(.space) {
                                self.triggerSpace()
                                return .handled
                            }
                            .onKeyPress(.upArrow) {
                                if let currentSelection = selection {
                                    selection = max(currentSelection - 1, 0)
                                }
                                return .handled
                            }
                            .onKeyPress(.downArrow) {
                                nextCandidate()
                                return .handled
                            }
                            .onKeyPress(.tab) {
                                self.imeState.toggle()
                                return .handled
                            }
                            .onKeyPress(.escape) {
                                self.textFieldFocus = false
                                return .handled
                            }
                    }
                Divider()
                if result.isEmpty && composingText.isEmpty {
                    Text("After you commit text they will be added here")
                        .foregroundStyle(.secondary)
                } else {
                    (Text(result) + Text(composingText.convertTarget).underline())
                        .font(.largeTitle)
                        .draggable(result + composingText.convertTarget)
                }
                Spacer()
                if !textFieldFocus {
                    Button {
                        textFieldFocus = true
                    } label: {
                        Label("Start input", systemImage: "square.and.pencil")
                            .font(.extraLargeTitle)
                            .padding(20)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
                if !imeState {
                    Text("IME OFF")
                        .font(.largeTitle)
                } else if selection == nil && !composingText.isEmpty {
                    Text("Press space to convert")
                        .foregroundStyle(.secondary)
                } else if candidateCount < 6 {
                    VStack(alignment: .center, spacing: 10) {
                        candidatesView
                    }
                } else {
                    ScrollView {
                        WrappingHStack(alignment: .center, horizontalSpacing: 10) {
                            candidatesView
                        }
                    }
                }
                Spacer()
                Button(imeState ? "IME OFF (tab)" : "IME ON (tab)") {
                    guard composingText.isEmpty else {
                        return
                    }
                    self.imeState.toggle()
                }
                .disabled(!composingText.isEmpty)
                .keyboardShortcut(.tab)
            }
            
            VStack(spacing: 30) {
                Button(action: {
                    self.copy()
                }) {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .padding(20)
                }
                .keyboardShortcut("c", modifiers: .command)
                Button(action: {
                    self.copy()
                    self.clear()
                }) {
                    Image(systemName: "scissors")
                        .padding(20)
                }
                .keyboardShortcut("x", modifiers: .command)
                Button(action: {
                    self.clear()
                }) {
                    Image(systemName: "xmark")
                        .padding(20)
                }
                .keyboardShortcut("x", modifiers: .command)
            }
            .font(.largeTitle)
        }
        .onAppear {
            self.converter.sendToDicdataStore(.setRequestOptions(Self.option))
            textFieldFocus = true
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}

class CommandOverrideUITextView: UITextView {
    var textViewCommands: TextViewCommands = .default

    @objc override func copy(_ sender: Any?) {
        if let copy = textViewCommands.copy {
            copy()
        } else {
            super.copy(sender)
        }
    }
    @objc override func cut(_ sender: Any?) {
        if let cut = textViewCommands.cut {
            cut()
        } else {
            super.cut(sender)
        }
    }
    @objc override func paste(_ sender: Any?) {
        if let paste = textViewCommands.paste {
            paste()
        } else {
            super.paste(sender)
        }
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // コマンドを有効にする
        if action == #selector(cut(_:)) && self.textViewCommands.cut != nil {
            return true
        }
        if action == #selector(copy(_:)) && self.textViewCommands.copy != nil {
            return true
        }
        if action == #selector(paste(_:)) && self.textViewCommands.paste != nil {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}


@MainActor struct TextViewCommands {
    var cut: (() -> ())?
    var copy: (() -> ())?
    var paste: (() -> ())?

    static let `default`: Self = TextViewCommands()
}

struct CommandOverrideTextView: UIViewRepresentable {

    @Binding var text: String
    var textViewCommands: TextViewCommands

    init(text: Binding<String>, TextViewCommands: TextViewCommands = .default) {
        self._text = text
        self.textViewCommands = TextViewCommands
    }

    func makeUIView(context: Context) -> CommandOverrideUITextView {
        let textView = CommandOverrideUITextView (frame: .zero)
        textView.textViewCommands = self.textViewCommands
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ uiView: CommandOverrideUITextView, context: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(text: $text)
    }

    class Coordinator: NSObject, UITextViewDelegate {

        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            text = textView.text ?? ""
        }
    }
}
