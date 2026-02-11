//
//  AppleAIImageProcessor.swift
//  Refine
//

import CoreImage
import Vision
import UIKit
import ImageIO
import AVFoundation

actor AppleAIImageProcessor {
    
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
        .useSoftwareRenderer: false,
        .cacheIntermediates: false,
        .highQualityDownsample: true
    ])
    
    func process(_ imageData: Data) async throws -> Data {
        // ✅ 1. 원본 메타데이터 추출
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            throw ProcessingError.invalidImageData
        }
        
        print("📋 원본 메타데이터 키: \(metadata.keys)")
        
        // ✅ 2. CIImage로 직접 로드 (orientation 자동 적용)
        guard let ciImage = CIImage(data: imageData)?.oriented(forExifOrientation: extractExifOrientation(from: metadata)) else {
            throw ProcessingError.invalidImageData
        }
        
        print("🎨 원본 이미지 크기: \(ciImage.extent.size)")
        
        // ✅ 3. 매우 섬세한 처리 (순정 카메라 느낌 유지)
        let enhanced = applySubtleEnhancement(ciImage)
        print("🎨 향상 완료: \(enhanced.extent.size)")
        
        // ✅ 4. 메타데이터 보존하며 저장
        return try await saveAsHEIFWithMetadata(enhanced, originalMetadata: metadata)
    }
    
    // MARK: - Extract EXIF Orientation
    
    private func extractExifOrientation(from metadata: [CFString: Any]) -> Int32 {
        if let orientation = metadata[kCGImagePropertyOrientation] as? Int32 {
            return orientation
        }
        return 1 // .up
    }
    
    // MARK: - Subtle Enhancement
    
    private func applySubtleEnhancement(_ image: CIImage) -> CIImage {
        var result = image
        
//        // 1. 매우 약한 노이즈 제거 (디테일 보존)
//        result = applyGentleNoiseReduction(result)
//        
//        // 2. 스마트 샤프닝 (텍스트/엣지만 강화)
//        result = applySmartSharpening(result)
//        
//        // 3. 미세 대비 조정
//        result = applyMicroContrast(result)
        
        return result
    }
    
    // MARK: - Gentle Noise Reduction
    
    private func applyGentleNoiseReduction(_ image: CIImage) -> CIImage {
        // 매우 약하게 적용 (거의 안 보이는 수준)
        guard let filter = CIFilter(name: "CINoiseReduction") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.005, forKey: "inputNoiseLevel") // 기존 0.01에서 절반으로
        filter.setValue(0.70, forKey: "inputSharpness")   // 더 샤프하게
        
        return filter.outputImage ?? image
    }
    
    // MARK: - Smart Sharpening
    
    private func applySmartSharpening(_ image: CIImage) -> CIImage {
        // Luminance만 샤프닝 (색상 아티팩트 방지)
        guard let filter = CIFilter(name: "CISharpenLuminance") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.3, forKey: kCIInputSharpnessKey) // 매우 섬세하게
        filter.setValue(2.0, forKey: kCIInputRadiusKey)    // 넓은 범위
        
        return filter.outputImage ?? image
    }
    
    // MARK: - Micro Contrast
    
    private func applyMicroContrast(_ image: CIImage) -> CIImage {
        // 디테일 대비 향상 (전체 대비 아님)
        guard let filter = CIFilter(name: "CIUnsharpMask") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.5, forKey: kCIInputRadiusKey)     // 작은 반경
        filter.setValue(0.15, forKey: kCIInputIntensityKey) // 약한 강도
        
        return filter.outputImage ?? image
    }
    
    // MARK: - Save with Metadata (고품질)
    
    private func saveAsHEIFWithMetadata(_ image: CIImage, originalMetadata: [CFString: Any]) async throws -> Data {
        print("💾 고품질 HEIF 저장 시작...")
        
        guard image.extent.isInfinite == false else {
            throw ProcessingError.renderFailed
        }
        
        // ✅ P3 컬러 스페이스 유지 (iPhone 순정과 동일)
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        
        // ✅ RGBA16으로 렌더링 (10bit HEIF 지원)
        guard let cgImage = context.createCGImage(
            image,
            from: image.extent,
            format: .RGBA16,  // 고품질
            colorSpace: colorSpace
        ) else {
            print("❌ CGImage 생성 실패, RGBA8로 재시도")
            // fallback
            guard let cgImage8 = context.createCGImage(
                image,
                from: image.extent,
                format: .RGBA8,
                colorSpace: colorSpace
            ) else {
                throw ProcessingError.renderFailed
            }
            return try saveWithCGImage(cgImage8, metadata: originalMetadata)
        }
        
        return try saveWithCGImage(cgImage, metadata: originalMetadata)
    }
    
    private func saveWithCGImage(_ cgImage: CGImage, metadata: [CFString: Any]) throws -> Data {
        let mutableData = NSMutableData()
        
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            "public.heic" as CFString,
            1,
            nil
        ) else {
            throw ProcessingError.exportFailed
        }
        
        // ✅ 원본 메타데이터 + 최고 품질 설정
        var properties = metadata
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImageDestinationLossyCompressionQuality] = 1.0 // 최고 품질
        
        // ✅ 잘못된 부분 제거 - 아래 코드 삭제
        // let heifProperties: [CFString: Any] = [
        //     kCGImagePropertyHEIFDictionary: [
        //         kCGImagePropertyHEIFPreserveHDRGainMap: true
        //     ]
        // ]
        // properties.merge(heifProperties) { (current, _) in current }
        
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw ProcessingError.exportFailed
        }
        
        print("✅ 고품질 HEIF 저장 완료: \(mutableData.count) bytes")
        return mutableData as Data
    }
}

enum ProcessingError: Error {
    case invalidImageData
    case renderFailed
    case exportFailed
    case modelNotAvailable
}
