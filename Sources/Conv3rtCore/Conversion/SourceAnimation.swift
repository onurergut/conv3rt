import Foundation
import ImageIO

/// Canonical animation properties used by inspection, decoding and encoding.
public enum SourceAnimation {
    /// Seconds as stored in the source. Prefer Image I/O's original delay over
    /// the playback delay, which may clamp a short frame to 0.1 seconds.
    /// Zero remains zero; callers decide whether their encoder can represent it.
    public static func duration(in properties: [CFString: Any]) -> Double? {
        let keys: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (key, unclamped, clamped) in keys {
            guard let dictionary = properties[key] as? [CFString: Any] else { continue }
            guard let value = dictionary[unclamped] ?? dictionary[clamped] else { continue }
            guard let number = value as? NSNumber else { return nil }
            let seconds = number.doubleValue
            return seconds.isFinite && seconds >= 0 ? seconds : nil
        }
        return nil
    }

    public static func loopCount(in properties: [CFString: Any]) -> Int? {
        let keys: [(CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFLoopCount),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSLoopCount),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPLoopCount),
        ]
        for (key, loopKey) in keys {
            guard let dictionary = properties[key] as? [CFString: Any],
                  let number = dictionary[loopKey] as? NSNumber else { continue }
            let count = number.doubleValue
            guard count.isFinite, count >= 0, count < Double(Int.max), count.rounded() == count else { return nil }
            return Int(count)
        }
        return nil
    }

    /// AVIF and JPEG XL have no public duration keys in the local Image I/O
    /// headers. Their multi-image sources are still animations; unknown timing
    /// must remain unknown instead of turning them into page stacks.
    public static func isAnimated(uti: String, count: Int, properties: [CFString: Any]) -> Bool {
        guard count > 1 else { return false }
        let families = ["public.png", "com.compuserve.gif", "public.heics", "org.webmproject.webp",
                        "public.avif", "public.jpeg-xl"]
        return families.contains { uti == $0 || UTTypeBridge.conformance(uti, toIdentifier: $0) }
            || duration(in: properties) != nil
            || loopCount(in: properties) != nil
    }
}
