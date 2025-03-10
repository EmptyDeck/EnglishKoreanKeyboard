import CoreML

class LanguageClassifierHandler {
    private var model: CRF?
    
    init() {
        loadModel()
    }
    
    private func loadModel() {
        guard let modelURL = Bundle.main.url(forResource: "CRF", withExtension: "mlmodelc") else {
            print("Error: CRF.mlmodelc not found in bundle")
            return
        }
        
        do {
            let configuration = MLModelConfiguration()
            let compiledModel = try CRF(contentsOf: modelURL, configuration: configuration)
            model = compiledModel
            print("Language classification model loaded successfully")
        } catch {
            print("Error loading CRF model: \(error)")
        }
    }
    
    func predict(text: String) -> (language: String, probability: Float)? {
        guard let model = model else {
            print("Model not loaded")
            return nil
        }
        
        do {
            // Use the generated CRFInput type
            let input = CRFInput(text: text) // Adjust if the initializer differs
            
            // Make prediction using the model
            let prediction = try model.prediction(input: input)
            
            // Extract label and probability from the generated CRFOutput
            let label = prediction.label
            // Use the correct property name for probabilities (assumed to be classProbabilities)
            guard let probability = prediction.classProbabilities?[label] else {
                print("Error: Could not retrieve probability for label \(label)")
                return nil
            }
            
            return (language: label, probability: Float(probability))
        } catch {
            print("Prediction error: \(error)")
            return nil
        }
    }
}
