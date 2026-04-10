//  Created by Marcin Krzyzanowski
//  https://github.com/krzyzanowskim/STTextView/blob/main/LICENSE.md

import AppKit
import STTextKitPlus
import CoreTextSwift
import STTextViewCommon

extension STTextView {

    /// This action method shows or hides the ruler, if the receiver is enclosed in a scroll view.
    @objc public func toggleRuler(_ sender: Any?) {
        isGutterVisible.toggle()
    }

    /// A Boolean value that controls whether the scroll view enclosing text views sharing the receiver’s layout manager displays the ruler.
    var isGutterVisible: Bool {
        set {
            if gutterView == nil, newValue == true {
                let gutterView = STGutterView()
                // estimate max gutter width
                gutterView.frame.origin = .zero
                gutterView.frame.size.width = max(gutterView.minimumThickness, CGFloat(textContentManager.length) / (1024 * 100))
                gutterView.frame.size.height = contentView.bounds.height
                gutterView.textColor = textColor.withAlphaComponent(0.45)
                gutterView.selectedLineTextColor = textColor
                gutterView.highlightSelectedLine = highlightSelectedLine
                gutterView.selectedLineHighlightColor = selectedLineHighlightColor
                gutterView.backgroundColor = backgroundColor
                if let enclosingScrollView {
                    enclosingScrollView.addFloatingSubview(gutterView, for: .horizontal)
                } else {
                    self.addSubview(gutterView)
                }
                self.gutterView = gutterView
                needsLayout = true
                layoutGutter()
            } else if newValue == false, let gutterView {
                gutterView.removeFromSuperview()
                self.gutterView = nil
                needsLayout = true
                layoutGutter()
            }
        }
        get {
            gutterView != nil
        }
    }

    func layoutGutter() {
        guard let gutterView, let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange else {
            return
        }

        gutterView.frame.size.height = contentView.bounds.height

        layoutGutterLineNumbers()
        layoutGutterMarkers()
    }



    private func layoutGutterLineNumbers() {
        guard let gutterView else {
            return
        }

        let lineTextAttributes: [NSAttributedString.Key: Any] = [
            .font: gutterView.font,
            .foregroundColor: gutterView.textColor
        ]

        let selectedLineTextAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: (gutterView.selectedLineTextColor ?? gutterView.textColor).cgColor
        ]

        // if empty document
        if textLayoutManager.documentRange.isEmpty {
            // Remove all existing cells for empty document
            gutterView.containerView.subviews.compactMap {
                $0 as? STGutterLineNumberCell
            }.forEach {
                $0.removeFromSuperviewWithoutNeedingDisplay()
            }

            if let selectionFrame = textLayoutManager.textSegmentFrame(at: textLayoutManager.documentRange.location, type: .standard) {
                let lineNumber = 1

                let ctNumberLine = CTLineCreateWithAttributedString(NSAttributedString(string: "\(lineNumber)", attributes: typingAttributes))
                let baselineParagraphStyle = typingAttributes[.paragraphStyle] as? NSParagraphStyle ?? defaultParagraphStyle
                let baselineOffset = -(ctNumberLine.typographicHeight() * (baselineParagraphStyle.stLineHeightMultiple - 1.0) / 2)

                var effectiveLineTextAttributes = lineTextAttributes
                if gutterView.highlightSelectedLine, !selectedLineTextAttributes.isEmpty {
                    effectiveLineTextAttributes.merge(selectedLineTextAttributes, uniquingKeysWith: { (_, new) in new })
                }

                let numberCell = STGutterLineNumberCell(
                    firstBaseline: ctNumberLine.typographicBounds().ascent - baselineOffset,
                    attributes: effectiveLineTextAttributes,
                    number: lineNumber
                )

                numberCell.insets = gutterView.insets

                if gutterView.highlightSelectedLine, textLayoutManager.textSelectionsRanges(.withoutInsertionPoints).isEmpty, !textLayoutManager.insertionPointSelections.isEmpty {
                    numberCell.layer?.backgroundColor = gutterView.selectedLineHighlightColor.cgColor
                }

                numberCell.frame = CGRect(
                    origin: CGPoint(
                        x: 0,
                        y: selectionFrame.origin.y
                    ),
                    size: CGSize(
                        width: gutterView.containerView.frame.width,
                        height: typingLineHeight
                    )
                ).pixelAligned

                gutterView.containerView.addSubview(numberCell)
            }
        } else if let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange {
            let visibleFragmentViews = STGutterCalculations.visibleFragmentViewsInViewport(
                fragmentViewMap: fragmentViewMap,
                viewportRange: viewportRange
            )

            guard !visibleFragmentViews.isEmpty else {
                return
            }

            // Count newlines before viewport to determine starting line number.
            // Direct character scan — O(n) but no ObjC dispatch overhead.
            let startLineIndex: Int
            let docStart = textLayoutManager.documentRange.location
            let vpStart = viewportRange.location
            if docStart.compare(vpStart) == .orderedSame {
                startLineIndex = 0
            } else if let storage = textContentManager as? NSTextContentStorage,
                      let textStorage = storage.textStorage {
                let endOffset = storage.offset(from: docStart, to: vpStart)
                if endOffset > 0, endOffset <= textStorage.length {
                    let nsString = textStorage.string as NSString
                    var count = 0
                    for i in 0..<endOffset {
                        if nsString.character(at: i) == 0x0A { count += 1 }
                    }
                    startLineIndex = count
                } else {
                    startLineIndex = 0
                }
            } else {
                startLineIndex = 0
            }

            // Collect reusable cells from the existing subviews
            var reusableCells: [STGutterLineNumberCell] = gutterView.containerView.subviews.compactMap {
                $0 as? STGutterLineNumberCell
            }

            var requiredWidthFitText = gutterView.minimumThickness
            var linesCount = 0
            var usedCellCount = 0

            for (layoutFragment, fragmentView) in visibleFragmentViews {
                let contentRangeInElement = (layoutFragment.textElement as? NSTextParagraph)?.paragraphContentRange ?? layoutFragment.rangeInElement

                for textLineFragment in layoutFragment.textLineFragments where (textLineFragment.isExtraLineFragment || layoutFragment.textLineFragments.first == textLineFragment) {
                    let lineNumber = startLineIndex + linesCount + 1

                    let isLineSelected = STGutterCalculations.isLineSelected(
                        textLineFragment: textLineFragment,
                        layoutFragment: layoutFragment,
                        contentRangeInElement: contentRangeInElement,
                        textLayoutManager: textLayoutManager
                    )

                    let (baselineYOffset, locationForFirstCharacter, cellFrame) = STGutterCalculations.calculateLineNumberMetrics(
                        for: textLineFragment,
                        in: layoutFragment,
                        fragmentViewFrame: fragmentView.frame
                    )

                    var effectiveLineTextAttributes = lineTextAttributes
                    if gutterView.highlightSelectedLine, isLineSelected, !selectedLineTextAttributes.isEmpty {
                        effectiveLineTextAttributes.merge(selectedLineTextAttributes, uniquingKeysWith: { (_, new) in new })
                    }
                    if let paragraphStyle = textLineFragment.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                        effectiveLineTextAttributes[.paragraphStyle] = paragraphStyle
                    }

                    // Reuse existing cell or create new one
                    let numberCell: STGutterLineNumberCell
                    if usedCellCount < reusableCells.count {
                        numberCell = reusableCells[usedCellCount]
                        numberCell.update(
                            firstBaseline: locationForFirstCharacter.y + baselineYOffset,
                            attributes: effectiveLineTextAttributes,
                            number: lineNumber
                        )
                    } else {
                        numberCell = STGutterLineNumberCell(
                            firstBaseline: locationForFirstCharacter.y + baselineYOffset,
                            attributes: effectiveLineTextAttributes,
                            number: lineNumber
                        )
                        gutterView.containerView.addSubview(numberCell)
                    }
                    numberCell.insets = gutterView.insets

                    if gutterView.highlightSelectedLine, isLineSelected,
                       textLayoutManager.textSelectionsRanges(.withoutInsertionPoints).isEmpty,
                       !textLayoutManager.insertionPointSelections.isEmpty {
                        numberCell.layer?.backgroundColor = gutterView.selectedLineHighlightColor.cgColor
                    } else {
                        numberCell.layer?.backgroundColor = nil
                    }

                    numberCell.frame = CGRect(
                        origin: CGPoint(
                            x: 0,
                            y: cellFrame.origin.y
                        ),
                        size: CGSize(
                            width: max(cellFrame.intersection(gutterView.containerView.frame).width, gutterView.containerView.frame.width),
                            height: cellFrame.size.height
                        )
                    ).pixelAligned

                    requiredWidthFitText = max(requiredWidthFitText, numberCell.intrinsicContentSize.width)
                    linesCount += 1
                    usedCellCount += 1
                }
            }

            // Remove excess reusable cells
            while usedCellCount < reusableCells.count {
                reusableCells[usedCellCount].removeFromSuperviewWithoutNeedingDisplay()
                usedCellCount += 1
            }

            if textLayoutManager.textViewportLayoutController.viewportRange != nil {
                let newGutterWidth = max(requiredWidthFitText, gutterView.minimumThickness)
                if !newGutterWidth.isAlmostEqual(to: gutterView.frame.size.width, tolerance: .ulpOfOne), newGutterWidth > gutterView.frame.size.width {
                    gutterView.frame.size.width = newGutterWidth
                }
            }
        }
    }

    private func layoutGutterMarkers() {
        guard let gutterView else {
            return
        }

        gutterView.layoutMarkers()
    }
}
