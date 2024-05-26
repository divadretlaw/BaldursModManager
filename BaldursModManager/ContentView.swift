//
//  ContentView.swift
//  BaldursModManager
//
//  Created by Justin Bush on 1/5/24.
//

import SwiftUI
import SwiftData
import AlertToast

let UIDELAY: CGFloat = 0.01

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \ModItem.order, order: .forward) private var modItems: [ModItem]
  @State private var selectedModItem: ModItem?
  @State private var showAlertForModDeletion = false
  @State private var showPermissionsView = false
  // Properties to store deletion details
  @State private var offsetsToDelete: IndexSet?
  @State private var modItemToDelete: ModItem?
  @State private var isFileTransferInProgress = false
  @State private var fileTransferProgress: Double = 0
  
  @State private var showXmlPreview = false
  @State private var previewXmlContent = ""
  
  @State private var showCheckmarkForRestore = false
  @State private var showCheckmarkForSync = false
  @State private var showConfirmationText = false
  @State private var confirmationMessage = ""
  
  @State private var showUnableToFindInfoJsonFileToast = false
  @State private var showUnableToReplaceExistingModToast = false
  @State private var showModSuccessfullyAddedToast = false
  @State private var showModSuccessfullyUpdatedToast = false
  
  @State private var showModSettingsSavedSuccessfullyToast = false
  @State private var showModSettingsRevertedSuccessfullyToast = false
  
  private let modItemManager = ModItemManager.shared
  @ObservedObject var debug = Debug.shared
  
  private func fetchEnabledModItemsSortedByOrder() -> [ModItem] {
    let predicate = #Predicate { (modItem: ModItem) in
      modItem.isEnabled == true
    }
    let sortDescriptor = SortDescriptor(\ModItem.order)
    let fetchDescriptor = FetchDescriptor<ModItem>(predicate: predicate, sortBy: [sortDescriptor])
    
    do {
      let modItems = try modelContext.fetch(fetchDescriptor)
      return modItems
    } catch {
      Debug.log("Failed to load ModItem model: \(error)")
      return []
    }
  }
  
  private func performInitialSetup() {
    FileUtility.createUserModsAndBackupFoldersIfNeeded()
    
    if debug.isActive {
      ModItemUtility.logModItems(fetchEnabledModItemsSortedByOrder())
      LsxUtilityTest.testXmlGenerationFromModSettingsLsxBackup()
    }
    
    // Backup modsettings.lsx on startup
    if let backupUrl = FileUtility.backupModSettingsLsxFile() {
      Debug.log("Successfully backed up modsettings.lsx at \(backupUrl)")
    }
  }
  
  private func selectModItem(_ item: ModItem?) {
    selectedModItem = item
    if let item = item {
      Debug.log("Selected mod item with order: \(item.order), name: \(item.modName)")
    }
  }
  
  var body: some View {
    NavigationSplitView {
      List(selection: $selectedModItem) {
        ForEach(modItems) { item in
          NavigationLink(value: item) {
            SidebarItemView(item: item) {
              selectModItem(item)
            }
          }
          .contentShape(Rectangle())
          .tag(item)
        }
        .onDelete(perform: deleteItems)
        .onMove(perform: moveItems)
      }
      .onChange(of: selectedModItem) {
        selectModItem(selectedModItem)
      }
      .navigationSplitViewColumnWidth(min: 200, ideal: 350)
      // MARK: Toolbar
      .toolbar {
        ToolbarItem {
          Button(action: addItem) {
            Label("Add Item", systemImage: "plus")
          }
        }
        ToolbarItemGroup(placement: .navigation) {
          if debug.isActive {
            Button(action: {
              openUserModsFolder()
            }) {
              Label("Open UserMods", systemImage: "folder")
            }
          }
          Button(action: {
            // preview modsettings.lsx
            previewModSettingsLsx()
          }) {
            Label("Preview modsettings.lsx", systemImage: "eye") // "command"
          }
          .sheet(isPresented: $showXmlPreview) {
            // Custom view for displaying the XML content
            XMLPreviewView(xmlContent: $previewXmlContent)
          }
        }
        ToolbarItem(placement: .principal) {
          if Debug.fileTransferUI || isFileTransferInProgress {
            ProgressView(value: fileTransferProgress, total: 1.0)
              .frame(width: 100)
              .opacity(fileTransferProgress > 0 ? 1 : 0)  // Fade out effect
          }
        }
        ToolbarItem(placement: .principal) {
          HStack {
            Button(action: {
              restoreDefaultModSettingsLsx()
              showCheckmarkForRestore = true
              confirmationMessage = "Restored!"
              showConfirmationText = true
              resetButtonAndMessage()
            }) {
              Label("Restore", systemImage: showCheckmarkForRestore ? "checkmark" : "gobackward")
            }
            Button(action: {
              generateAndSaveModSettingsLsx()
              showCheckmarkForSync = true
              confirmationMessage = "Saved!"
              showConfirmationText = true
              resetButtonAndMessage()
            }) {
              Label("Sync", systemImage: showCheckmarkForSync ? "checkmark" : "arrow.triangle.2.circlepath")
            }
            if showConfirmationText {
              Text(confirmationMessage)
                .opacity(showConfirmationText ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: showConfirmationText)
            }
          }
        }
      }
    } detail: {
      if let selectedModItem {
        ModItemDetailView(item: selectedModItem, deleteAction: deleteItem)
      } else {
        WelcomeDetailView()
      }
    }
    .navigationDestination(for: ModItem.self) { item in
      ModItemDetailView(item: item, deleteAction: deleteItem)
    }
    // MARK: Alerts
    .alert(isPresented: $showAlertForModDeletion) {
      Alert(
        title: Text("Remove Mod"),
        message: Text("Are you sure you want to remove this mod? It will be moved to the trash."),
        primaryButton: .destructive(Text("Move to Trash")) {
          deleteModItems(at: offsetsToDelete, itemToDelete: modItemToDelete)
        },
        secondaryButton: .cancel()
      )
    }
    // MARK: Toasts
    .toast(isPresenting: $showUnableToFindInfoJsonFileToast, duration: 6) {
      AlertToast(displayMode: .banner(.pop), type: .error(.red), title: "Invalid mod folder: Unable to locate Info.json file")
    }
    .toast(isPresenting: $showUnableToReplaceExistingModToast, duration: 6) {
      AlertToast(displayMode: .banner(.pop), type: .error(.red), title: "Unable to replace existing mod with newer version")
    }
    .toast(isPresenting: $showModSuccessfullyAddedToast, duration: 3) {
      AlertToast(displayMode: .banner(.pop), type: .complete(.green), title: "Mod added")
    }
    .toast(isPresenting: $showModSuccessfullyAddedToast, duration: 3) {
      AlertToast(displayMode: .banner(.pop), type: .complete(.green), title: "Mod successfully updated")
    }
    .toast(isPresenting: $showModSettingsSavedSuccessfullyToast, duration: 4) {
      AlertToast(type: .complete(.green), title: "Mods have been applied successfully")
    }
    .toast(isPresenting: $showModSettingsRevertedSuccessfullyToast, duration: 4) {
      AlertToast(type: .complete(.gray), title: "Mods have been reverted")
    }
    .sheet(isPresented: $showPermissionsView) {
      PermissionsView(onDismiss: {
        self.showPermissionsView = false
      })
    }
    .onAppear {
      performInitialSetup()
      if Debug.permissionsView {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          self.showPermissionsView = true
        }
      }
    }
  }
  
  private func resetButtonAndMessage() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { // Adjust the time as needed
      showCheckmarkForRestore = false
      showCheckmarkForSync = false
      withAnimation {
        showConfirmationText = false
      }
    }
  }
  
  private func generateAndSaveModSettingsLsx() {
    Debug.log("User did select generateAndSaveModSettingsLsx()")
    if let xmlAttributes = LsxUtility.parseFileContents(FileUtility.getDefaultModSettingsLsxFile()) {
      let modItems = fetchEnabledModItemsSortedByOrder()
      
      let xmlBuilder = XMLBuilder(xmlAttributes: xmlAttributes, modItems: modItems)
      let xmlString = xmlBuilder.buildXMLString()
      Debug.log(xmlString)
      FileUtility.replaceModSettingsLsxInUserDocuments(withFileContents: xmlString)
      showModSettingsSavedSuccessfullyToast = true
    }
  }
  
  private func restoreDefaultModSettingsLsx() {
    Debug.log("User did select restoreDefaultModSettingsLsx()")
    if let xmlAttributes = LsxUtility.parseFileContents(FileUtility.getDefaultModSettingsLsxFile()) {
      let xmlBuilder = XMLBuilder(xmlAttributes: xmlAttributes, modItems: [])
      let xmlString = xmlBuilder.buildXMLString()
      Debug.log(xmlString)
      FileUtility.replaceModSettingsLsxInUserDocuments(withFileContents: xmlString)
      showModSettingsRevertedSuccessfullyToast = true
    }
  }
  
  private func previewModSettingsLsx() {
    if let xmlAttributes = LsxUtility.parseFileContents(FileUtility.getDefaultModSettingsLsxFile()) {
      let modItems = fetchEnabledModItemsSortedByOrder()
      
      let xmlBuilder = XMLBuilder(xmlAttributes: xmlAttributes, modItems: modItems)
      previewXmlContent = xmlBuilder.buildXMLString()
      showXmlPreview = true
    }
  }
  
  private func openUserModsFolder() {
    if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      let userModsURL = appSupportURL.appendingPathComponent(Constants.ApplicationSupportFolderName)
      NSWorkspace.shared.open(userModsURL)
    }
  }
  
  private func addItem() {
    selectFile()
  }
  
  private func moveItems(from source: IndexSet, to destination: Int) {
    var reorderedItems = modItems
    reorderedItems.move(fromOffsets: source, toOffset: destination)
    // Update the 'order' of each 'ModItem' to its new index
    for (index, item) in reorderedItems.enumerated() {
      item.order = index
      Debug.log("Updated mod item order: \(item.modName) to \(index)")
    }
    // Save the context
    do {
      try modelContext.save()
      Debug.log("Successfully saved context after moving items")
    } catch {
      Debug.log("Error saving context: \(error)")
    }
  }
  
  private func selectFile() {
    let openPanel = NSOpenPanel()
    openPanel.canChooseFiles = false
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = false
    openPanel.begin { response in
      if response == .OK, let selectedDirectory = openPanel.url {
        Debug.log("Selected directory: \(selectedDirectory.path)")
        parseImportedModFolder(at: selectedDirectory)
      }
    }
  }
  
  private func parseImportedModFolder(at url: URL) {
    if let contents = getDirectoryContents(at: url) {
      // Find info.json file
      if let infoJsonUrl = contents.first(where: { $0.caseInsensitiveCompare("info.json") == .orderedSame }) {
        let fullPath = url.appendingPathComponent(infoJsonUrl).path
        
        if let infoDict = parseJsonToDict(atPath: fullPath) {
          Debug.log("JSON contents: \n\(infoDict)")
          createNewModItemFrom(infoDict: infoDict, infoJsonPath: fullPath, directoryContents: contents)
        } else {
          Debug.log("Error parsing JSON content. Bring up manual entry screen.")
        }
      } else {
        Debug.log("Error: Unable to locate info.json file of imported mod")
        showUnableToFindInfoJsonFileToast = true
      }
    }
  }
  
  private func getModItem(byUuid uuid: String) -> ModItem? {
    return modItems.first(where: { $0.modUuid == uuid })
  }
  
  private func deleteModItem(byUuid uuid: String) -> Bool {
    if let modItemToDelete = getModItem(byUuid: uuid) {
      withAnimation {
        if modItemToDelete.isEnabled {
          modItemManager.movePakFileToOriginalLocation(modItemToDelete)
        }
        modelContext.delete(modItemToDelete)
        FileUtility.moveModItemToTrash(modItemToDelete)
        try? modelContext.save()
        updateOrderOfModItems()
      }
      return true
    } else {
      Debug.log("Error: No ModItem found with UUID: \(uuid)")
      return false
    }
  }
  
  private func createNewModItemFrom(infoDict: [String:String], infoJsonPath: String, directoryContents: [String]) {
    let directoryURL = URL(fileURLWithPath: infoJsonPath).deletingLastPathComponent()
    
    if let pakFileString = getPakFileString(fromDirectoryContents: directoryContents) {
      var name, folder, uuid, md5: String?
      for (key, value) in infoDict {
        switch key.lowercased() {
        case "name": name = value
        case "folder": folder = value
        case "uuid": uuid = value
        case "md5": md5 = value
        default: break
        }
      }
      
      if let name = name, let folder = folder, let uuid = uuid, let md5 = md5 {
        var newOrderNumber = nextOrderValue()
        var replaceWithOrderNumber: Int?
        
        // TODO: Prompt user for confirmation on replacement
        if let modItemNeedsReplacing = getModItem(byUuid: uuid) {
          replaceWithOrderNumber = modItemNeedsReplacing.order
          let success = deleteModItem(byUuid: uuid)
          if success {
            if let oldOrderNumber = replaceWithOrderNumber {
              newOrderNumber = oldOrderNumber
              showModSuccessfullyUpdatedToast = true
            }
          } else {
            Debug.log("Error: Unable to delete mod \(modItemNeedsReplacing.modName)")
            showUnableToReplaceExistingModToast = true
            return
          }
        }
        
        withAnimation {
          let newModItem = ModItem(order: newOrderNumber, directoryUrl: directoryURL, directoryPath: directoryURL.path, directoryContents: directoryContents, pakFileString: pakFileString, name: name, folder: folder, uuid: uuid, md5: md5)
          // Check for optional keys
          for (key, value) in infoDict {
            switch key.lowercased() {
            case "author": newModItem.modAuthor = value
            case "description": newModItem.modDescription = value
            case "created": newModItem.modCreatedDate = value
            case "group": newModItem.modGroup = value
            case "version": newModItem.modVersion = value
            default: break
            }
          }
          
          Debug.log("Adding new mod item with order: \(newOrderNumber), name: \(name)")
          addNewModItem(newModItem, orderNumber: newOrderNumber, fromDirectoryUrl: directoryURL)
        }
      }
      
    } else {
      Debug.log("Error: Unable to resolve pakFileString from \(directoryContents)")
    }
  }
  
  private func addNewModItem(_ modItem: ModItem, orderNumber: Int, fromDirectoryUrl directoryUrl: URL) {
    modelContext.insert(modItem)
    
    DispatchQueue.main.asyncAfter(deadline: .now() + UIDELAY) {
      selectModItem(modItem)
      Debug.log("Added new mod item with order: \(orderNumber), name: \(modItem.modName)")
    }
    
    importModFolderAndUpdateModItemDirectoryPath(at: directoryUrl, modItem: modItem, progress: $fileTransferProgress)
  }
  
  private func getDirectoryContents(at url: URL) -> [String]? {
    do {
      let fileManager = FileManager.default
      let contents = try fileManager.contentsOfDirectory(atPath: url.path)
      Debug.log("Directory contents: \(contents)")
      return contents
    } catch {
      Debug.log("Error listing directory contents: \(error)")
    }
    return nil
  }
  
  private func getPakFileString(fromDirectoryContents directoryContents: [String]) -> String? {
    for file in directoryContents {
      if file.lowercased().hasSuffix(".pak") {
        return file
      }
    }
    return nil
  }
  
  func parseJsonToDict(atPath filePath: String) -> [String: String]? {
    if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
      do {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        if let dict = jsonObject as? [String: Any],
           let mods = dict["Mods"] as? [[String: Any]],
           let firstMod = mods.first {
          
          var result: [String: String] = [:]
          
          // Extract key-value pairs from the "Mods" dictionary
          for (key, value) in firstMod {
            if let stringValue = value as? String {
              result[key] = stringValue
            }
          }
          
          // Extract MD5 from the top-level dictionary
          if let md5 = dict["MD5"] as? String {
            result["MD5"] = md5
          }
          
          return result
        }
      } catch {
        Debug.log("Error parsing JSON: \(error.localizedDescription)")
      }
    }
    
    return nil
  }
  
  // Triggered by UI delete button
  private func deleteItem(item: ModItem) {
    modItemToDelete = item
    offsetsToDelete = nil
    showAlertForModDeletion = true
  }
  
  // Triggered by menu bar item Edit > Delete
  private func deleteItems(offsets: IndexSet) {
    offsetsToDelete = offsets
    modItemToDelete = nil
    showAlertForModDeletion = true
  }
  
  private func deleteModItems(at offsets: IndexSet? = nil, itemToDelete: ModItem? = nil) {
    var indexToSelect: Int?
    
    withAnimation {
      if let offsets = offsets {
        for index in offsets.sorted().reversed() {
          if index < modItems.count {
            let modItem = modItems[index]
            if modItem.isEnabled {
              modItemManager.movePakFileToOriginalLocation(modItem)
            }
            indexToSelect = index
            modelContext.delete(modItem)
            FileUtility.moveModItemToTrash(modItem)
            Debug.log("Deleted mod item with order: \(modItem.order), name: \(modItem.modName)")
          }
        }
      } else if let modItem = itemToDelete {
        if modItem.isEnabled {
          modItemManager.movePakFileToOriginalLocation(modItem)
        }
        if let index = modItems.firstIndex(of: modItem) {
          indexToSelect = index
          modelContext.delete(modItem)
          FileUtility.moveModItemToTrash(modItem)
          Debug.log("Deleted mod item with order: \(modItem.order), name: \(modItem.modName)")
        }
      }
      try? modelContext.save() // Save the context after deletion
      updateOrderOfModItems()  // Update the order of remaining items
      
      offsetsToDelete = nil
      modItemToDelete = nil
      
      if let index = indexToSelect {
        DispatchQueue.main.asyncAfter(deadline: .now() + UIDELAY) {
          selectModItem(modItems[index - 1])
          Debug.log("Selected mod item order after deletion: \(modItems[index - 1])")
        }
      }
    }
  }
  
  private func updateOrderOfModItems() {
    var updatedOrder = 0
    for item in modItems.sorted(by: { $0.order < $1.order }) {
      item.order = updatedOrder
      Debug.log("Updated order for item \(item.modName) to \(updatedOrder)")
      updatedOrder += 1
    }
    // Save the context after reordering
    do {
      try modelContext.save()
      Debug.log("Successfully saved context after reordering items")
    } catch {
      Debug.log("Error saving context after reordering: \(error)")
    }
  }
  
  private func nextOrderValue() -> Int {
    if modItems.isEmpty {
      return 0  // If there are no items, start with 0
    } else {
      // Otherwise, find the maximum order and add 1
      return (modItems.max(by: { $0.order < $1.order })?.order ?? 0) + 1
    }
  }
  
  private func importModFolderAndUpdateModItemDirectoryPath(
    at originalPath: URL, modItem: ModItem, progress: Binding<Double>
  ) {
    // Mark transfer as started
    DispatchQueue.main.async {
      self.isFileTransferInProgress = true
    }
    
    importModFolderAndReturnNewDirectoryPath(
      at: originalPath,
      progressHandler: { progressValue in
        DispatchQueue.main.async {
          progress.wrappedValue = progressValue.fractionCompleted
        }
      },
      completionHandler: { directoryPath in
        DispatchQueue.main.async {
          if let directoryPath = directoryPath {
            modItem.directoryUrl = URL(fileURLWithPath: directoryPath)
            modItem.directoryPath = directoryPath
          } else {
            Debug.log("Error: Unable to resolve directoryPath from importModFolderAndReturnNewDirectoryPath(at: \(originalPath))")
          }
          // Mark transfer as finished
          self.isFileTransferInProgress = false
          SoundUtility.play(systemSound: .mount)
          
          showModSuccessfullyAddedToast = true
          
          // Fade out the ProgressView after 1.5 seconds if fileTransferUI is not active
          if (!Debug.fileTransferUI) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
              self.fileTransferProgress = 0
            }
          }
        }
      }
    )
  }
  
  
  private func importModFolderAndReturnNewDirectoryPath(at originalPath: URL, progressHandler: @escaping (Progress) -> Void, completionHandler: @escaping (String?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let fileManager = FileManager.default
      guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        completionHandler(nil)
        return
      }
      
      let destinationURL = appSupportURL.appendingPathComponent(Constants.ApplicationSupportFolderName).appendingPathComponent(Constants.UserModsFolderName).appendingPathComponent(originalPath.lastPathComponent)
      let progress = Progress(totalUnitCount: 1)  // You might want to find a better way to estimate progress
      
      do {
        if UserSettings.shared.makeCopyOfModFolderOnImport {
          progressHandler(progress)
          try fileManager.copyItem(at: originalPath, to: destinationURL)
        } else {
          progressHandler(progress)
          try fileManager.moveItem(at: originalPath, to: destinationURL)
        }
        
        progress.completedUnitCount = 1
        DispatchQueue.main.async {
          completionHandler(destinationURL.path)
        }
      } catch {
        DispatchQueue.main.async {
          Debug.log("Error handling mod folder: \(error)")
          completionHandler(nil)
        }
      }
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: ModItem.self, inMemory: true)
}

struct ToolbarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(3)
      .background(configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear)
      .cornerRadius(5)
  }
}

struct IconLabelView: View {
  let icon: String
  let label: String
  
  var body: some View {
    VStack {
      Image(systemName: icon)
        .font(.system(size: 18))
        .opacity(0.75)
      Text(label)
        .font(.system(size: 10))
        .opacity(0.75)
    }
  }
}
