import CoreML
import Accelerate

class LanguageClassifierHandler {
    private let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private var charToIndex: [Character: Int] = [:]
    private let maxSequenceLength = 20

    init() {
        for (idx, char) in alphabet.enumerated() {
            charToIndex[char] = idx
        }
    }

    func preprocess(word: String) -> (x: MLMultiArray, lengths: MLMultiArray)? {
        let validChars = word.filter { charToIndex.keys.contains($0) }
        guard !validChars.isEmpty else {
            print("Error: No valid characters in '\(word)'")
            return nil
        }
        
        let sequenceLength = min(validChars.count, maxSequenceLength)
        do {
            // 1. 입력 형상
            let xArray = try MLMultiArray(
                shape: [1, maxSequenceLength, 52] as [NSNumber], // [1, 20, 52]
                dataType: .float32 // 2. 데이터 타입 수정 (.int32 → .float32)
            )
            
            let count = xArray.count
            var zero: Float = 0.0
            vDSP_vfill(&zero, xArray.dataPointer.assumingMemoryBound(to: Float.self), 1, vDSP_Length(count))

            
            // 3. lengths 배열 형상 및 타입 수정
            let lengthsArray = try MLMultiArray(
                shape: [1] as [NSNumber],
                dataType: .float32 // 모델이 Float 타입을 기대함
            )
            
            // 4. 원-핫 인코딩 수정
            for (timeStep, char) in validChars.prefix(maxSequenceLength).enumerated() {
                guard let idx = charToIndex[char] else { continue }
                print("timeStep: ", timeStep, " / idx: ", idx)
                xArray[[0, timeStep, idx] as [NSNumber]] = 1.0 // Float 값 할당
            }
            
//            for i in 0..<xArray.shape[0].intValue {
//                for j in 0..<xArray.shape[1].intValue {
//                    for k in 0..<xArray.shape[2].intValue {
//                        let value = xArray[[i as NSNumber, j as NSNumber, k as NSNumber]].floatValue
//                        print("xArray[\(i)][\(j)][\(k)] = \(value)")
//                    }
//                }
//            }
            
            // 5. 패딩 처리 활성화
            if validChars.count < maxSequenceLength {
                for timeStep in validChars.count..<maxSequenceLength {
                    xArray[[0, timeStep, 0] as [NSNumber]] = 0.0
                }
            }
            
            // 6. lengths 배열 값 설정
            lengthsArray[0] = NSNumber(value: Float(sequenceLength))
            
            return (xArray, lengthsArray)
            
        } catch {
            print("Preprocessing failed: \(error)")
            return nil
        }
    }

    func predict(word: String) -> Float? {
        guard let (xInput, lengthsInput) = preprocess(word: word) else {
            print("전처리 실패: \(word)")
            return nil
        } 

        do {
            let model = try wrongHangulChecker()
            let input = wrongHangulCheckerInput(input_1: xInput, input_2: lengthsInput)
            let output = try model.prediction(input: input)
            
            // 안전한 값 추출
            guard output.output.count >= 1 else {
                print("출력 형식 오류")
                return nil
            }
            
            let probability = output.output[0].floatValue
            return probability
            
        } catch {
            print("예측 실패: \(error.localizedDescription)")
            return nil
        }
    }
}
