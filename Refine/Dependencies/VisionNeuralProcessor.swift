//
//  AI.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/12.
//

//
//  VisionNeuralProcessor.swift
//  Refine
//

import CoreImage
import Vision
import UIKit
import ImageIO

actor VisionNeuralProcessor {
    
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])
    
    func process(_ imageData: Data) async throws -> Data {
        // 1. 메타데이터 추출
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            throw ProcessingError.invalidImageData
        }
        
        // 2. CIImage 로드
        guard let ciImage = CIImage(data: imageData)?.oriented(forExifOrientation: extractExifOrientation(from: metadata)) else {
            throw ProcessingError.invalidImageData
        }
        
        print("🧠 Neural Engine 처리 시작: \(Int(ciImage.extent.width))x\(Int(ciImage.extent.height))")
        
        // 3. Neural Engine으로 피사체 감지
        let subjectMask = try await detectSubject(ciImage)
        
        if let mask = subjectMask {
            print("✅ 피사체 감지 성공 - 선택적 처리")
            // 피사체가 있으면 선택적 향상
            let enhanced = enhanceWithSubjectMask(ciImage, mask: mask)
            return try await saveAsHEIFWithMetadata(enhanced, originalMetadata: metadata)
        } else {
            print("⚠️ 피사체 없음 - 전체 향상")
            // 피사체 없으면 전체 약하게 향상
            let enhanced = enhanceGlobal(ciImage)
            return try await saveAsHEIFWithMetadata(enhanced, originalMetadata: metadata)
        }
    }
    
    // MARK: - Subject Detection (Neural Engine)
    
    private func detectSubject(_ image: CIImage) async throws -> CIImage? {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw ProcessingError.renderFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // ✅ VNGeneratePersonSegmentationRequest - Neural Engine 사용
            let request = VNGeneratePersonSegmentationRequest { request, error in
                if let error = error {
                    print("⚠️ 피사체 감지 실패: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let observation = request.results?.first as? VNPixelBufferObservation else {
                    print("⚠️ 피사체 없음")
                    continuation.resume(returning: nil)
                    return
                }
                
                // CVPixelBuffer → CIImage
                let maskImage = CIImage(cvPixelBuffer: observation.pixelBuffer)
                print("✅ 피사체 마스크 생성 완료")
                continuation.resume(returning: maskImage)
            }
            
            // ✅ Neural Engine 사용 설정
            request.qualityLevel = .accurate  // Neural Engine 최대 활용
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("⚠️ Vision 에러: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - Enhance with Subject Mask
    
    private func enhanceWithSubjectMask(_ image: CIImage, mask: CIImage) -> CIImage {
        // 마스크를 이미지 크기에 맞춤
        let scaledMask = mask.transformed(by: CGAffineTransform(
            scaleX: image.extent.width / mask.extent.width,
            y: image.extent.height / mask.extent.height
        ))
        
        // 1. 피사체 영역 추출
        let subject = extractSubject(image, mask: scaledMask)
        
        // 2. 배경 영역 추출
        let background = extractBackground(image, mask: scaledMask)
        
        // 3. 피사체: 강하게 샤프닝
        let enhancedSubject = sharpenSubject(subject)
        
        // 4. 배경: 약하게 노이즈 제거
        let cleanBackground = cleanBackground(background)
        
        // 5. 합성
        return enhancedSubject.composited(over: cleanBackground)
    }
    
    // MARK: - Extract Subject
    
    private func extractSubject(_ image: CIImage, mask: CIImage) -> CIImage {
        // 마스크를 사용해 피사체만 추출
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: mask
        ])
    }
    
    // MARK: - Extract Background
    
    private func extractBackground(_ image: CIImage, mask: CIImage) -> CIImage {
        // 마스크 반전 (피사체 제외)
        guard let invertedMask = CIFilter(name: "CIColorInvert", parameters: [
            kCIInputImageKey: mask
        ])?.outputImage else {
            return image
        }
        
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: invertedMask
        ])
    }
    
    // MARK: - Sharpen Subject
    
    private func sharpenSubject(_ subject: CIImage) -> CIImage {
        var result = subject
        
        // 1. Unsharp Mask (강하게)
        if let filter = CIFilter(name: "CIUnsharpMask") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(1.5, forKey: kCIInputRadiusKey)
            filter.setValue(0.8, forKey: kCIInputIntensityKey)  // 피사체는 강하게
            result = filter.outputImage ?? result
        }
        
        // 2. Sharpen Luminance
        if let filter = CIFilter(name: "CISharpenLuminance") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(0.5, forKey: kCIInputSharpnessKey)
            result = filter.outputImage ?? result
        }
        
        // 3. 대비 약간 증가
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(1.1, forKey: kCIInputContrastKey)
            result = filter.outputImage ?? result
        }
        
        return result
    }
    
    // MARK: - Clean Background
    
    private func cleanBackground(_ background: CIImage) -> CIImage {
        var result = background
        
        // 배경은 약하게 노이즈만 제거
        if let filter = CIFilter(name: "CINoiseReduction") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(0.01, forKey: "inputNoiseLevel")  // 약하게
            filter.setValue(0.60, forKey: "inputSharpness")
            result = filter.outputImage ?? result
        }
        
        return result
    }
    
    // MARK: - Enhance Global (피사체 없을 때)
    
    private func enhanceGlobal(_ image: CIImage) -> CIImage {
        var result = image
        
        // 전체적으로 매우 약하게만
        if let filter = CIFilter(name: "CISharpenLuminance") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(0.2, forKey: kCIInputSharpnessKey)  // 아주 약하게
            result = filter.outputImage ?? result
        }
        
        return result
    }
    
    // MARK: - Helpers
    
    private func extractExifOrientation(from metadata: [CFString: Any]) -> Int32 {
        if let orientation = metadata[kCGImagePropertyOrientation] as? Int32 {
            return orientation
        }
        return 1
    }
    
    private func saveAsHEIFWithMetadata(_ image: CIImage, originalMetadata: [CFString: Any]) async throws -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        
        guard let cgImage = context.createCGImage(
            image,
            from: image.extent,
            format: .RGBA16,
            colorSpace: colorSpace
        ) else {
            // fallback to RGBA8
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
        
        var properties = metadata
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImageDestinationLossyCompressionQuality] = 1.0
        
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw ProcessingError.exportFailed
        }
        
        print("✅ Neural Engine 처리 완료: \(mutableData.count) bytes")
        return mutableData as Data
    }
}
