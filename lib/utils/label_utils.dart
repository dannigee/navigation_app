/// Display label for a macro/preset item: [name] with [numberDisplay] in
/// parentheses when a custom name exists, otherwise [fallback] (or
/// [numberDisplay] itself if no [fallback] is given).
String formatItemLabel(String? name, String numberDisplay, {String? fallback}) =>
    (name == null || name.isEmpty)
        ? (fallback ?? numberDisplay)
        : '$name ($numberDisplay)';
