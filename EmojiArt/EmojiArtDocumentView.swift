//
//  EmojiArtDocumentView.swift
//  EmojiArt
//
//  Created by CS193p Instructor on 4/26/21.
//  Copyright © 2021 Stanford University. All rights reserved.
//

import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument
    
    let defaultEmojiFontSize: CGFloat = 40
    
    var body: some View {
        VStack(spacing: 0) {
            documentBody
            palette
        }
    }
    
    var documentBody: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.overlay(
                    OptionalImage(uiImage: document.backgroundImage)
                        .scaleEffect(zoomScale)
                        .position(convertFromEmojiCoordinates((0,0), in: geometry))
                )
                .gesture(doubleTapToZoom(in: geometry.size).exclusively(before: tapToUnselectAll()))
                
                if document.backgroundImageFetchStatus == .fetching {
                    ProgressView().scaleEffect(2)
                } else {
                    ForEach(document.emojis) { emoji in
                        ZStack {
                            Text(emoji.text)
                                .font(.system(size: fontSize(for: emoji)))
                                .gesture(doubleTapToDelete(emoji).exclusively(before: tapToSelect_unselect(emoji)))
                            if selectedEmoji.contains(emoji) {
                                Rectangle()
                                    .stroke()
                                    .frame(width: fontSize(for: emoji), height: fontSize(for: emoji))
                            }
                        }
                        .scaleEffect(zoomScale * emojiZoomScale(for: emoji))
                        .position(position(for: emoji, in: geometry))
                        .gesture(dragGesture())
                    }
                }
            }
            .clipped()
            .onDrop(of: [.plainText,.url,.image], isTargeted: nil) { providers, location in
                drop(providers: providers, at: location, in: geometry)
            }
            .gesture(panGesture().simultaneously(with: zoomGesture()))
        }
    }
    
    // MARK: - Drag and Drop
    
    private func drop(providers: [NSItemProvider], at location: CGPoint, in geometry: GeometryProxy) -> Bool {
        var found = providers.loadObjects(ofType: URL.self) { url in
            document.setBackground(.url(url.imageURL))
        }
        if !found {
            found = providers.loadObjects(ofType: UIImage.self) { image in
                if let data = image.jpegData(compressionQuality: 1.0) {
                    document.setBackground(.imageData(data))
                }
            }
        }
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                if let emoji = string.first, emoji.isEmoji {
                    document.addEmoji(
                        String(emoji),
                        at: convertToEmojiCoordinates(location, in: geometry),
                        size: defaultEmojiFontSize / zoomScale
                    )
                }
            }
        }
        return found
    }
    
    // MARK: - Positioning/Sizing Emoji
    
    private func position(for emoji: EmojiArtModel.Emoji, in geometry: GeometryProxy) -> CGPoint {
        convertFromEmojiCoordinatesOnDrag(for: emoji, atLocation: (emoji.x, emoji.y), in: geometry)
    }
    
    private func fontSize(for emoji: EmojiArtModel.Emoji) -> CGFloat {
        CGFloat(emoji.size)
    }
    
    private func convertToEmojiCoordinates(_ location: CGPoint, in geometry: GeometryProxy) -> (x: Int, y: Int) {
        let center = geometry.frame(in: .local).center
        let location = CGPoint(
            x: (location.x - panOffset.width - center.x) / zoomScale,
            y: (location.y - panOffset.height - center.y) / zoomScale
        )
        return (Int(location.x), Int(location.y))
    }
    
    private func convertFromEmojiCoordinatesOnDrag(for emoji: EmojiArtModel.Emoji, atLocation: (x: Int, y: Int), in geometry: GeometryProxy) -> CGPoint {
        let center = geometry.frame(in: .local).center
        
        return CGPoint(
            x: center.x + CGFloat(atLocation.x) * zoomScale + panOffset.width + dragOffset(for: emoji).width,
            y: center.y + CGFloat(atLocation.y) * zoomScale + panOffset.height + dragOffset(for: emoji).height
        )
    }
    
    private func convertFromEmojiCoordinates(_ location: (x: Int, y: Int), in geometry: GeometryProxy) -> CGPoint {
        let center = geometry.frame(in: .local).center
        return CGPoint(
            x: center.x + CGFloat(location.x) * zoomScale + panOffset.width,
            y: center.y + CGFloat(location.y) * zoomScale + panOffset.height
        )
    }
    
    // MARK: - Deletion
    
    private func doubleTapToDelete(_ emoji: EmojiArtModel.Emoji) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                // delete only selected emoji
                guard selectedEmoji.contains(emoji) else {return}
                document.delete(emoji)
            }
    }
    
    // MARK: - Selection
    
    @State private var selectedEmoji = Set<EmojiArtModel.Emoji>()
    
    private func tapToSelect_unselect(_ emoji: EmojiArtModel.Emoji) -> some Gesture {
        TapGesture()
            .onEnded {
                select_unselect(emoji)
            }
    }
    
    private func select_unselect(_ emoji: EmojiArtModel.Emoji ) {
        selectedEmoji.toggleMembership(of: emoji)
        
        //check whether 'emoji' belongs to 'steadyStateEmojiScales'
        if !steadyStateEmojiScales.contains(where: {$0.emoji == emoji}) {
            // if it is not - add it to the 'steadyStateEmojiScales'
            steadyStateEmojiScales.append((emoji, 1))
        }
        // check whether 'emoji' belongs to 'steadyStateDragOffsets'
        if !steadyStateDragOffsets.contains(where: {$0.emoji == emoji}) {
            // if it is not - add it to the 'steadyStateDragOffsets'
            steadyStateDragOffsets.append((emoji, .zero))
        }
    }
    
    private func tapToUnselectAll() -> some Gesture {
        TapGesture()
            .onEnded {
                unselect()
            }
    }
    
    private func unselect() {
        selectedEmoji.removeAll()
    }
    
    // MARK: - Zooming
    
    @State private var steadyStateZoomScale: CGFloat = 1
    @GestureState private var gestureZoomScale: CGFloat = 1
    
    private var zoomScale: CGFloat {
        steadyStateZoomScale * (selectedEmoji.isEmpty ? gestureZoomScale : 1)
    }
    
    typealias SteadyStateEmojiScale = (emoji: EmojiArtModel.Emoji, scale: CGFloat)
    @State private var steadyStateEmojiScales = [SteadyStateEmojiScale]()
    
    private func emojiZoomScale(for emoji: EmojiArtModel.Emoji) -> CGFloat {
 
        if let sses = steadyStateEmojiScales.first(where: {$0.emoji == emoji}) {
            return sses.scale * (selectedEmoji.contains(emoji) ? gestureZoomScale : 1)
        } else {
            return 1
        }
    }
    
    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .updating($gestureZoomScale) { latestGestureScale, gestureZoomScale, _ in
                gestureZoomScale = latestGestureScale
            }
            .onEnded { gestureScaleAtEnd in
                steadyStateZoomScale *= (selectedEmoji.isEmpty ? gestureScaleAtEnd : 1)
                
                selectedEmoji.forEach { emoji in
                    if let index = steadyStateEmojiScales.firstIndex(where: {$0.emoji == emoji}),
                       let sses = steadyStateEmojiScales.first(where: {$0.emoji == emoji}) {
                        
                        let sses_new = (emoji, sses.scale * gestureScaleAtEnd)
                        steadyStateEmojiScales.remove(at: index)
                        steadyStateEmojiScales.append(sses_new)
                    }
                }
            }
    }
    
    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation {
                    zoomToFit(document.backgroundImage, in: size)
                }
            }
    }
    
    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0  {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height
            steadyStatePanOffset = .zero
            steadyStateZoomScale = min(hZoom, vZoom)
        }
    }
    
    // MARK: - Dragging of Emoji
    
    typealias FinalStateDragOffset = (emoji: EmojiArtModel.Emoji, offset: CGSize)
    @State private var steadyStateDragOffsets = [FinalStateDragOffset]()
    
    @GestureState private var gestureDragOffset: CGSize = .zero
    
    private func dragOffset(for emoji: EmojiArtModel.Emoji) -> CGSize {
        if let ssdo = steadyStateDragOffsets.first(where: {$0.emoji == emoji}) {
            return (ssdo.offset + (selectedEmoji.contains(emoji) ? gestureDragOffset : .zero)) * zoomScale
        } else {
            return .zero
        }
    }
    
    private func dragGesture() -> some Gesture {
        DragGesture()
            .updating($gestureDragOffset) { latestDragGestureValue, gestureDragOffset, _ in
                gestureDragOffset = latestDragGestureValue.translation / zoomScale
            }
            .onEnded { finalDragGestureValue in
                selectedEmoji.forEach { emoji in
                    if let index = steadyStateDragOffsets.firstIndex(where: {$0.emoji == emoji}),
                       let ssdo = steadyStateDragOffsets.first(where: {$0.emoji == emoji}) {
                        
                        let ssdo_new = (emoji, ssdo.offset + finalDragGestureValue.translation / zoomScale)
                        steadyStateDragOffsets.remove(at: index)
                        steadyStateDragOffsets.append(ssdo_new)
                    }
                }
            }
    }
    
    // MARK: - Panning
    
    @State private var steadyStatePanOffset: CGSize = CGSize.zero
    @GestureState private var gesturePanOffset: CGSize = CGSize.zero
    
    private var panOffset: CGSize {
        (steadyStatePanOffset + gesturePanOffset) * zoomScale
    }
    
    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset) { latestPanGestureValue, gesturePanOffset, _ in
                gesturePanOffset = latestPanGestureValue.translation / zoomScale
            }
            .onEnded { finalPanGestureValue in
                steadyStatePanOffset = steadyStatePanOffset + (finalPanGestureValue.translation / zoomScale)
            }
    }

    // MARK: - Palette
    
    var palette: some View {
        ScrollingEmojisView(emojis: testEmojis)
            .font(.system(size: defaultEmojiFontSize))
    }
    
    let testEmojis = "😀😷🦠💉👻👀🐶🌲🌎🌞🔥🍎⚽️🚗🚓🚲🛩🚁🚀🛸🏠⌚️🎁🗝🔐❤️⛔️❌❓✅⚠️🎶➕➖🏳️"
}

struct ScrollingEmojisView: View {
    let emojis: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(emojis.map { String($0) }, id: \.self) { emoji in
                    Text(emoji)
                        .onDrag { NSItemProvider(object: emoji as NSString) }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        EmojiArtDocumentView(document: EmojiArtDocument())
    }
}
