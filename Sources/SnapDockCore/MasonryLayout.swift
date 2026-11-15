import CoreGraphics

public enum MasonryLayout {
  public static func frames(
    heightRatios: [CGFloat],
    columns: Int,
    width: CGFloat,
    spacing: CGFloat,
    maximumRatio: CGFloat = 2.5
  ) -> (frames: [CGRect], height: CGFloat) {
    let columnCount = max(columns, 1)
    let columnWidth = max((width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount), 0)
    var heights = Array(repeating: CGFloat(0), count: columnCount)
    let frames = heightRatios.map { ratio in
      let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
      let validRatio = ratio.isFinite && ratio > 0 ? ratio : 1
      let height = columnWidth * min(validRatio, maximumRatio)
      let frame = CGRect(
        x: CGFloat(column) * (columnWidth + spacing),
        y: heights[column],
        width: columnWidth,
        height: height
      )
      heights[column] += height + spacing
      return frame
    }
    let total = (heights.max() ?? 0) - (heightRatios.isEmpty ? 0 : spacing)
    return (frames, max(total, 0))
  }
}
