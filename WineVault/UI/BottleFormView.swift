import AVFoundation
import SwiftUI
import UIKit
import WineVaultDomain

struct BottleFormView: View {
    @ObservedObject var store: InventoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var form: BottleForm
    @State private var tagEntry = ""
    @State private var attemptedSave = false
    @State private var capturedPhoto: Data?
    @State private var showingCamera = false
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private let isEditing: Bool

    init(store: InventoryStore, bottle: Bottle?) {
        self.store = store
        isEditing = bottle != nil
        _form = State(initialValue: bottle.map(BottleForm.init(bottle:)) ?? BottleForm())
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                detailsSection
                quantitySection
                tagsSection
                drinkBySection
                photoSection
                notesSection
            }
            .disabled(store.isSaving)
            .navigationTitle(isEditing ? "Edit Bottle" : "Add Bottle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(store.isSaving)
                        .accessibilityIdentifier("cancelBottleButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isSaving ? "Saving…" : "Save") { save() }
                        .disabled(store.isSaving)
                        .accessibilityIdentifier("saveBottleButton")
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { image in
                    capturedPhoto = image.jpegData(compressionQuality: 0.86)
                }
                .ignoresSafeArea()
            }
            .alert("Bottle not saved", isPresented: saveErrorPresented) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "Unknown error")
            }
            .interactiveDismissDisabled(store.isSaving)
        }
    }

    private var identitySection: some View {
        Section("Identity") {
            TextField("Name", text: $form.name)
                .textContentType(.name)
                .accessibilityIdentifier("bottleNameField")
            validation(.nameRequired)
            TextField("Producer", text: $form.producer)
                .accessibilityIdentifier("producerField")
            TextField("Vintage", text: $form.vintage)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("vintageField")
            validation(.vintageInvalid)
        }
    }

    private var detailsSection: some View {
        Section("Origin and storage") {
            TextField("Region", text: $form.region)
                .accessibilityIdentifier("regionField")
            TextField("Grape", text: $form.grape)
                .accessibilityIdentifier("grapeField")
            TextField("Storage location", text: $form.storageLocation)
                .accessibilityIdentifier("storageLocationField")
        }
    }

    private var quantitySection: some View {
        Section("Quantity") {
            Stepper(value: $form.quantity, in: 1...999) {
                Text("Quantity: \(form.quantity)")
            }
            .accessibilityLabel("Bottle quantity")
            .accessibilityValue(String(form.quantity))
            .accessibilityIdentifier("quantityStepper")
            validation(.quantityMustBePositive)
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            HStack {
                TextField("Add a tag", text: $tagEntry)
                    .submitLabel(.done)
                    .onSubmit(addTag)
                    .accessibilityIdentifier("tagField")
                Button("Add", action: addTag)
                    .disabled(tagEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("addTagButton")
            }
            ForEach(form.tags, id: \.self) { tag in
                HStack {
                    Text(tag)
                    Spacer()
                    Button("Remove \(tag)", systemImage: "xmark.circle") {
                        form.tags.removeAll { $0 == tag }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Remove tag \(tag)")
                }
            }
        }
    }

    private var drinkBySection: some View {
        Section("Drink by") {
            Toggle("Set drink-by date", isOn: drinkByEnabled)
                .accessibilityIdentifier("drinkByToggle")
            if form.drinkBy != nil {
                DatePicker(
                    "Drink by",
                    selection: Binding(
                        get: { form.drinkBy ?? Date() },
                        set: { form.drinkBy = $0 }
                    ),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("drinkByPicker")
            }
        }
    }

    private var photoSection: some View {
        Section("Label photo") {
            Text(
                "Optional. Camera access is used only when you choose to photograph a label; "
                    + "the photo stays in Wine Vault's private storage."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let capturedPhoto, let image = UIImage(data: capturedPhoto) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .accessibilityLabel("Captured label photo")
            } else if !form.photos.isEmpty {
                Label(
                    form.photos.count == 1 ? "1 label photo saved" : "\(form.photos.count) label photos saved",
                    systemImage: "photo"
                )
            }
            cameraAction
            if cameraStatus == .denied || cameraStatus == .restricted {
                Label(
                    "Camera access is unavailable. You can still enter and save every bottle detail manually.",
                    systemImage: "camera.fill"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cameraDeniedMessage")
            } else if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                Text("This device has no camera. Manual entry remains available.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cameraUnavailableMessage")
            }
        }
    }

    @ViewBuilder
    private var cameraAction: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera),
           cameraStatus != .denied,
           cameraStatus != .restricted {
            Button("Take Label Photo", systemImage: "camera") { requestCamera() }
                .accessibilityLabel("Take optional label photo")
                .accessibilityHint("Requests camera access and opens the camera. Manual entry does not require it.")
                .accessibilityIdentifier("takePhotoButton")
        }
    }

    private var notesSection: some View {
        Section("Tasting notes") {
            TextEditor(text: $form.notes)
                .frame(minHeight: 100)
                .accessibilityLabel("Tasting notes")
                .accessibilityIdentifier("notesField")
        }
    }

    private var drinkByEnabled: Binding<Bool> {
        Binding(
            get: { form.drinkBy != nil },
            set: { form.drinkBy = $0 ? Date() : nil }
        )
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    @ViewBuilder
    private func validation(_ issue: BottleFormValidationIssue) -> some View {
        if attemptedSave, form.validationErrors.contains(issue) {
            Label(issue.message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(issue.message)")
                .accessibilityIdentifier("validation_\(issue.rawValue)")
        }
    }

    private func addTag() {
        let value = tagEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !form.tags.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else {
            return
        }
        form.tags.append(value)
        tagEntry = ""
    }

    private func save() {
        attemptedSave = true
        guard form.validationErrors.isEmpty else { return }
        Task {
            if await store.save(form, photoData: capturedPhoto) {
                dismiss()
            }
        }
    }

    private func requestCamera() {
        switch cameraStatus {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                cameraStatus = granted ? .authorized : .denied
                showingCamera = granted
            }
        case .denied, .restricted:
            break
        @unknown default:
            cameraStatus = .restricted
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
