import Models
import SwiftUI
import Tokens

/// The icon and color trigger of the label sheet (MATRIX-77): a capsule
/// that shows the current icon on its color and opens the picker popover.
public struct LabelIconColorPicker: View {
    let name: String
    @Binding var colorIndex: Int?
    @Binding var icon: String?

    @State private var isPresented = false

    public init(name: String, colorIndex: Binding<Int?>, icon: Binding<String?>) {
        self.name = name
        _colorIndex = colorIndex
        _icon = icon
    }

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                LabelIcon(name: name, colorIndex: colorIndex, icon: icon, size: 22)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 3)
            .padding(.trailing, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Choose an icon and color")
        .accessibilityLabel("Icon and color")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            LabelIconColorPickerContent(name: name, colorIndex: $colorIndex, icon: $icon)
        }
    }
}

/// The picker popover: a row of color swatches over a grid of icons
/// (MATRIX-77). The first swatch and the first icon cell are "none": the
/// neutral fill, and the name's first letter.
public struct LabelIconColorPickerContent: View {
    let name: String
    @Binding var colorIndex: Int?
    @Binding var icon: String?

    public init(name: String, colorIndex: Binding<Int?>, icon: Binding<String?>) {
        self.name = name
        _colorIndex = colorIndex
        _icon = icon
    }

    private var iconColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(LabelToken.pickerIconCellSize), spacing: LabelToken.pickerSpacing),
            count: LabelToken.pickerIconColumns
        )
    }

    private var swatchColumns: [GridItem] {
        // Seven swatches per row: 13 entries make two balanced rows.
        Array(repeating: GridItem(.fixed(LabelToken.pickerSwatchSize), spacing: LabelToken.pickerSpacing + 4), count: 7)
    }

    private var monogram: String {
        let letter = ChatLabel(name: name).monogram
        return letter.isEmpty ? "A" : letter
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LabelToken.pickerPadding) {
            Text("Color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: LabelToken.pickerSpacing + 2) {
                swatch(nil, name: "No Color")
                ForEach(LabelToken.palette.indices, id: \.self) { index in
                    swatch(index, name: LabelToken.palette[index].name)
                }
            }

            Text("Icon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: iconColumns, alignment: .leading, spacing: LabelToken.pickerSpacing) {
                iconCell(nil) {
                    Text(monogram).font(.system(size: LabelToken.pickerIconGlyphSize, weight: .bold))
                }
                ForEach(LabelToken.icons, id: \.self) { symbol in
                    iconCell(symbol) {
                        Image(systemName: symbol).font(.system(size: LabelToken.pickerIconGlyphSize))
                    }
                }
            }
        }
        .padding(LabelToken.pickerPadding)
        .fixedSize()
    }

    private func swatch(_ index: Int?, name: String) -> some View {
        let isSelected = colorIndex == index
        return Button {
            colorIndex = index
        } label: {
            Circle()
                .fill(LabelToken.fill(for: index))
                .frame(width: LabelToken.pickerSwatchSize, height: LabelToken.pickerSwatchSize)
                .overlay {
                    if index == nil {
                        Image(systemName: "slash.circle")
                            .font(.system(size: LabelToken.pickerSwatchSize * 0.6))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(LabelToken.pickerSelectionWidth + 1)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: LabelToken.pickerSelectionWidth)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func iconCell(_ symbol: String?, @ViewBuilder glyph: () -> some View) -> some View {
        let isSelected = icon == symbol
        let shape = RoundedRectangle(cornerRadius: LabelToken.pickerIconCellCornerRadius, style: .continuous)
        return Button {
            icon = symbol
        } label: {
            glyph()
                .frame(width: LabelToken.pickerIconCellSize, height: LabelToken.pickerIconCellSize)
                .background(shape.fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear))
                .overlay {
                    if isSelected {
                        shape.strokeBorder(Color.accentColor, lineWidth: LabelToken.pickerSelectionWidth)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(symbol ?? "First letter")
        .accessibilityLabel(symbol ?? "First letter")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
