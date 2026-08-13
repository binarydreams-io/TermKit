import Testing

@testable import TUIAgentUI

struct InteractionPromptTests {
    @Test("Permission focus stays trapped within explicit choices")
    func permissionFocus() {
        var prompt = PermissionPrompt(
            requestedAction: "Delete generated files",
            resources: [".build"],
            risk: .destructive,
            choices: [
                PermissionChoice(scope: .deny, label: "Deny", risk: .low),
                PermissionChoice(scope: .once, label: "Allow once", risk: .destructive),
                PermissionChoice(scope: .persistent, label: "Always allow", risk: .persistent),
            ]
        )

        prompt.moveFocus(by: 20)

        #expect(prompt.trapsFocus)
        #expect(prompt.requiresExplicitAction)
        #expect(prompt.focusedChoice.scope == .persistent)
        #expect(prompt.focusedChoice.requiresStrongEmphasis)
    }

    @MainActor
    @Test("Permission actions return the selected risk choice")
    func permissionAction() {
        final class Recorder {
            var choice: PermissionChoice?
        }

        let recorder = Recorder()
        let actions = PermissionPromptActions { recorder.choice = $0 }
        let choice = PermissionChoice(scope: .once, label: "Allow once", risk: .elevated)

        actions.choose(choice)

        #expect(recorder.choice == choice)
    }

    @Test("Single selection rejects multiple values")
    func singleSelectionValidation() {
        let question = Question(
            id: "mode",
            title: "Choose a mode",
            kind: .singleSelection,
            options: [QuestionOption(id: "a", label: "A"), QuestionOption(id: "b", label: "B")],
            validationRules: [.required]
        )
        let prompt = QuestionPrompt(
            questions: [question],
            answers: ["mode": .optionIDs(["a", "b"])]
        )

        #expect(prompt.validationErrors(forQuestionAt: 0) == [.incompatibleAnswer])
    }

    @Test("Selection answers reject option identifiers that the question does not define")
    func unknownOptionValidation() {
        let question = Question(
            id: "mode",
            title: "Choose a mode",
            kind: .multipleSelection,
            options: [QuestionOption(id: "known", label: "Known")]
        )
        let prompt = QuestionPrompt(
            questions: [question],
            answers: ["mode": .optionIDs(["known", "unknown"])]
        )

        #expect(prompt.validationErrors(forQuestionAt: 0) == [.incompatibleAnswer])
    }

    #if compiler(>=6.1)
        @Test("Question construction rejects duplicate option identifiers")
        func duplicateOptionIdentifiers() async {
            await #expect(processExitsWith: .failure) {
                _ = Question(
                    id: "mode",
                    title: "Choose a mode",
                    kind: .singleSelection,
                    options: [
                        QuestionOption(id: "duplicate", label: "First"),
                        QuestionOption(id: "duplicate", label: "Second"),
                    ]
                )
            }
        }
    #endif

    @Test("Multiple and custom answers enforce validation rules")
    func answerValidation() {
        let prompt = QuestionPrompt(
            questions: [
                Question(
                    id: "targets",
                    title: "Choose targets",
                    kind: .multipleSelection,
                    options: [QuestionOption(id: "app", label: "App"), QuestionOption(id: "tests", label: "Tests")],
                    validationRules: [.minimumSelections(2)]
                ),
                Question(
                    id: "reason",
                    title: "Explain",
                    kind: .customText,
                    validationRules: [.required, .minimumTextLength(5)]
                ),
            ],
            answers: [
                "targets": .optionIDs(["app"]),
                "reason": .text("no"),
            ]
        )

        #expect(prompt.validationErrors(forQuestionAt: 0) == [.tooFewSelections(minimum: 2)])
        #expect(prompt.validationErrors(forQuestionAt: 1) == [.textTooShort(minimum: 5)])
    }

    @Test("Question steps advance only after a valid answer")
    func stepNavigation() {
        let questions = [
            Question(
                id: "confirm",
                title: "Continue?",
                kind: .singleSelection,
                options: [QuestionOption(id: "yes", label: "Yes")],
                validationRules: [.required]
            ),
            Question(id: "note", title: "Note", kind: .customText),
        ]
        var prompt = QuestionPrompt(questions: questions)
        var state = QuestionPromptState()

        #expect(state.moveToNextStep(in: prompt) == false)
        prompt.setAnswer(.optionIDs(["yes"]), forQuestionID: "confirm")
        let didAdvance = state.moveToNextStep(in: prompt)
        #expect(didAdvance)
        #expect(state.stepIndex == 1)

        state.moveToPreviousStep()
        #expect(state.stepIndex == 0)
    }
}
