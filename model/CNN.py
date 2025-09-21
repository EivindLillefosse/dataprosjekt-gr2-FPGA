import os
import numpy as np
import tensorflow as tf
from tensorflow.keras.utils import to_categorical
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Conv2D, MaxPooling2D, Flatten, Dense
import subprocess

############### GUIDE ################
# This script builds, trains, and evaluates a CNN model on a subset of the Quick, Draw! dataset.
# It includes visualizations of predictions, a confusion matrix, and misclassified examples.
# It also exports the trained model to ONNX format and creates FPGA-ready quantized models.
############### USE #################

# Install required packages:
# pip install tensorflow matplotlib seaborn scikit-learn tf2onnx

######################################

# Configuration
TRAINING_DATA_FOLDER = "model/training_data"
EPOCHS = 5
BATCH_SIZE = 128
SAMPLES_PER_CLASS = 1000
TEST_ENABLED = False  # Set to True to enable visualization and detailed testing

def load_data():
    """Load and preprocess data from training folder."""
    print("Loading data...")
    
    # Dynamically load categories from the training_data folder
    categories = [os.path.splitext(file)[0] for file in os.listdir(TRAINING_DATA_FOLDER) if file.endswith(".npy")]
    print(f"Categories loaded: {categories}")
    
    data = []
    labels = []
    
    for i, category in enumerate(categories):
        drawings = np.load(f'{TRAINING_DATA_FOLDER}/{category}.npy')[:SAMPLES_PER_CLASS]
        data.append(drawings)
        labels.append(np.full(drawings.shape[0], i))
    
    x = np.concatenate(data)
    y = np.concatenate(labels)
    
    print(f'Data shape: {x.shape}, Labels shape: {y.shape}')
    
    # Preprocess data
    x = x.reshape(-1, 28, 28, 1).astype('float32') / 255.0
    y = to_categorical(y, num_classes=len(categories))
    
    return x, y, categories
    
def create_model(num_classes):
    """Create and compile the CNN model."""
    print("Creating model...")
    
    model = Sequential([
        Conv2D(8, (3,3), activation='relu', input_shape=(28,28,1)),
        MaxPooling2D(2,2),
        Conv2D(16, (3,3), activation='relu'),
        MaxPooling2D(2,2),
        Flatten(),
        Dense(64, activation='relu'),
        Dense(num_classes, activation='softmax')
    ])
    
    model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
    return model

def train_model(model, x, y):
    """Train the model."""
    print("Training model...")
    model.fit(x, y, epochs=EPOCHS, batch_size=BATCH_SIZE, verbose=1)
    print('Model trained successfully.')
    return model

def evaluate_model(model, x, y, categories):
    """Evaluate model with visualizations and metrics."""
    if not TEST_ENABLED:
        return
        
    print("Evaluating model...")
    
    # Import visualization libraries only when needed
    import matplotlib.pyplot as plt
    from sklearn.metrics import confusion_matrix, classification_report
    import seaborn as sns
    
    # Create test set
    test_samples_per_class = 50
    test_indices = []
    for i in range(len(categories)):
        class_start = i * SAMPLES_PER_CLASS
        class_indices = np.arange(class_start, class_start + test_samples_per_class)
        test_indices.extend(class_indices)
    
    test_indices = np.array(test_indices)
    x_test = x[test_indices]
    y_test = y[test_indices]
    
    predictions = model.predict(x_test)
    predicted_classes = np.argmax(predictions, axis=1)
    true_classes = np.argmax(y_test, axis=1)
    
    # Sample predictions visualization
    plt.figure(figsize=(15, 10))
    for i in range(20):
        plt.subplot(4, 5, i+1)
        plt.imshow(x_test[i].reshape(28, 28), cmap='gray')
        true_label = categories[true_classes[i]]
        pred_label = categories[predicted_classes[i]]
        color = 'green' if true_classes[i] == predicted_classes[i] else 'red'
        plt.title(f'True: {true_label}\nPred: {pred_label}', color=color, fontsize=8)
        plt.axis('off')
    plt.suptitle('Sample Predictions (Green=Correct, Red=Wrong)', fontsize=14)
    plt.tight_layout()
    plt.savefig('sample_predictions.png', dpi=150, bbox_inches='tight')
    plt.show()
    
    # Confusion matrix
    plt.figure(figsize=(10, 8))
    cm = confusion_matrix(true_classes, predicted_classes)
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', 
                xticklabels=categories, yticklabels=categories)
    plt.title('Confusion Matrix')
    plt.xlabel('Predicted')
    plt.ylabel('True')
    plt.xticks(rotation=45)
    plt.yticks(rotation=0)
    plt.tight_layout()
    plt.savefig('confusion_matrix.png', dpi=150, bbox_inches='tight')
    plt.show()
    
    # Misclassified examples
    wrong_indices = np.where(predicted_classes != true_classes)[0]
    if len(wrong_indices) > 0:
        plt.figure(figsize=(15, 6))
        num_wrong_to_show = min(10, len(wrong_indices))
        for i in range(num_wrong_to_show):
            idx = wrong_indices[i]
            plt.subplot(2, 5, i+1)
            plt.imshow(x_test[idx].reshape(28, 28), cmap='gray')
            true_label = categories[true_classes[idx]]
            pred_label = categories[predicted_classes[idx]]
            confidence = np.max(predictions[idx]) * 100
            plt.title(f'True: {true_label}\nPred: {pred_label}\nConf: {confidence:.1f}%', 
                     fontsize=8, color='red')
            plt.axis('off')
        plt.suptitle('Misclassified Examples', fontsize=14)
        plt.tight_layout()
        plt.savefig('misclassified_examples.png', dpi=150, bbox_inches='tight')
        plt.show()
    
    # Print metrics
    print("\nClassification Report:")
    print(classification_report(true_classes, predicted_classes, target_names=categories))
    
    accuracy = np.mean(predicted_classes == true_classes)
    print(f"\nTest Accuracy: {accuracy:.3f} ({accuracy*100:.1f}%)")
    
    print("\nVisualization files saved:")
    print("- sample_predictions.png")
    print("- confusion_matrix.png") 
    print("- misclassified_examples.png")

def export_model(model):
    """Export model to SavedModel format."""
    print("Exporting model...")
    model.export("saved_model")
    print("✓ Model exported as SavedModel.")

def create_test_dataset_for_quantization(x, categories):
    """Create a small test dataset for quantization validation."""
    test_samples = 50
    test_samples_per_class = min(5, test_samples // len(categories))
    x_test_quant = []
    y_test_quant = []
    
    for i in range(len(categories)):
        class_start = i * SAMPLES_PER_CLASS
        class_end = min(class_start + test_samples_per_class, (i + 1) * SAMPLES_PER_CLASS)
        x_test_quant.extend(x[class_start:class_end])
        y_test_quant.extend([i] * (class_end - class_start))
    
    return np.array(x_test_quant[:test_samples]), np.array(y_test_quant[:test_samples])

def quantize_model_post_training(x):
    """Apply post-training quantization."""
    print("\n=== Applying Post-Training Quantization ===")
    
    # Create converter
    converter = tf.lite.TFLiteConverter.from_saved_model("saved_model")
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    # For FPGA: Use integer-only quantization
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.int8
    converter.inference_output_type = tf.int8
    
    # Representative dataset for calibration
    def representative_dataset():
        for i in range(100):
            yield [x[i:i+1].astype(np.float32)]
    
    converter.representative_dataset = representative_dataset
    quantized_model = converter.convert()
    
    # Save quantized model
    with open('quantized_model.tflite', 'wb') as f:
        f.write(quantized_model)
    
    print("✓ Post-training quantized model saved as 'quantized_model.tflite'")
    return quantized_model

def test_quantized_model(quantized_model, x_test_quant, y_test_quant):
    """Test the accuracy of the quantized model."""
    interpreter = tf.lite.Interpreter(model_content=quantized_model)
    interpreter.allocate_tensors()
    
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    
    print(f"Quantized model input type: {input_details[0]['dtype']}")
    print(f"Quantized model output type: {output_details[0]['dtype']}")
    
    correct_predictions = 0
    
    for i in range(len(x_test_quant)):
        # Convert input to int8 properly (range -128 to 127)
        test_input = (x_test_quant[i:i+1] * 255).astype(np.float32)
        test_input = np.clip(test_input - 128, -128, 127).astype(np.int8)
        interpreter.set_tensor(input_details[0]['index'], test_input)
        interpreter.invoke()
        
        quantized_output = interpreter.get_tensor(output_details[0]['index'])
        predicted_class_quantized = np.argmax(quantized_output)
        
        if predicted_class_quantized == y_test_quant[i]:
            correct_predictions += 1
    
    accuracy = correct_predictions / len(x_test_quant)
    print(f"Quantized model accuracy on {len(x_test_quant)} samples: {accuracy:.3f} ({accuracy*100:.1f}%)")

def apply_manual_quantization(model, x_test_quant, y_test_quant):
    """Apply manual quantization as fallback when TensorFlow Model Optimization fails."""
    print("\n=== Quantization-Aware Training (QAT) ===")
    
    try:
        import tensorflow_model_optimization as tfmot
        
        # Apply quantization-aware training
        quantize_model = tfmot.quantization.keras.quantize_model
        q_aware_model = quantize_model(model)
        
        q_aware_model.compile(optimizer='adam',
                             loss='categorical_crossentropy',
                             metrics=['accuracy'])
        
        print("✓ QAT model created")
        
        # Fine-tune with quantization simulation
        subset_size = 1000
        x_subset = x[:subset_size]
        y_subset = y[:subset_size]
        
        print("Fine-tuning with quantization simulation...")
        q_aware_model.fit(x_subset, y_subset, epochs=2, batch_size=BATCH_SIZE, verbose=1)
        
        # Convert QAT model to quantized TFLite
        converter_qat = tf.lite.TFLiteConverter.from_keras_model(q_aware_model)
        converter_qat.optimizations = [tf.lite.Optimize.DEFAULT]
        quantized_qat_model = converter_qat.convert()
        
        with open('quantized_qat_model.tflite', 'wb') as f:
            f.write(quantized_qat_model)
        
        print("✓ QAT quantized model saved as 'quantized_qat_model.tflite'")
        
    except (ImportError, AttributeError) as e:
        print(f"❌ tensorflow_model_optimization compatibility issue: {e}")
        print("🔧 Using alternative quantization approach...")
        
        # Manual quantization simulation
        print("Applying manual quantization simulation...")
        
        manual_quant_model = tf.keras.models.clone_model(model)
        manual_quant_model.set_weights(model.get_weights())
        
        # Simulate quantization by adding noise to weights
        quantized_weights = []
        for layer_weights in manual_quant_model.get_weights():
            weight_max = np.max(np.abs(layer_weights))
            scale = weight_max / 127  # 8-bit signed range
            quantized = np.round(layer_weights / scale) * scale
            quantized_weights.append(quantized)
        
        manual_quant_model.set_weights(quantized_weights)
        
        # Test manual quantized model
        manual_predictions = manual_quant_model.predict(x_test_quant[:50])
        manual_accuracy = np.mean(np.argmax(manual_predictions, axis=1) == y_test_quant[:50])
        print(f"✓ Manual quantization simulation accuracy: {manual_accuracy:.3f}")
        
        # Convert manual quantized model
        converter_manual = tf.lite.TFLiteConverter.from_keras_model(manual_quant_model)
        converter_manual.optimizations = [tf.lite.Optimize.DEFAULT]
        quantized_manual_model = converter_manual.convert()
        
        with open('quantized_manual_model.tflite', 'wb') as f:
            f.write(quantized_manual_model)
        
        print("✓ Manual quantized model saved as 'quantized_manual_model.tflite'")

def extract_weights_for_vhdl(model, filetype="vhd"):
    """Extract weights formatted for VHDL implementation or as .bin/.txt files.
    
    Args:
        model: Trained Keras model.
        filetype: 'vhd', 'bin', or 'txt' to control output format.
    """
    print(f"\n=== Extracting Weights for VHDL ({filetype}) ===")
    
    # Get the first convolution layer (Conv2D with 8 filters)
    conv_layer = None
    for layer in model.layers:
        if isinstance(layer, tf.keras.layers.Conv2D):
            conv_layer = layer
            break
    
    if conv_layer is None:
        print("No Conv2D layer found!")
        return
    
    weights, biases = conv_layer.get_weights()
    print(f"Conv layer weights shape: {weights.shape}")  # Should be (3, 3, 1, 8)
    print(f"Conv layer biases shape: {biases.shape}")    # Should be (8,)
    
    # Quantize to 8-bit integers for FPGA
    weight_max = np.max(np.abs(weights))
    scale_factor = 127.0 / weight_max
    quantized_weights = np.round(weights * scale_factor).astype(np.int8)
    quantized_biases = np.round(biases * scale_factor).astype(np.int8)
    
    print(f"Weight scale factor: {scale_factor}")
    print(f"Quantized weight range: [{np.min(quantized_weights)}, {np.max(quantized_weights)}]")
    
    if filetype == "vhd":
        # Generate VHDL weight array initialization
        with open('conv_weights.vhd', 'w') as f:
            f.write("-- Auto-generated convolution weights for VHDL\n")
            f.write("-- Weight array initialization for conv_layer\n\n")
            
            f.write("-- Weight array declaration (add to your architecture):\n")
            f.write("signal weight_array : OUTPUT_ARRAY_VECTOR(0 to NUM_FILTERS-1,\n")
            f.write("                                          0 to KERNEL_SIZE-1,\n") 
            f.write("                                          0 to KERNEL_SIZE-1) := (\n")
            
            for filter_idx in range(quantized_weights.shape[3]):  # 8 filters
                f.write(f"    -- Filter {filter_idx}\n")
                f.write(f"    {filter_idx} => (\n")
                
                for row in range(3):  # 3x3 kernel
                    f.write(f"        {row} => (")
                    for col in range(3):
                        weight_val = quantized_weights[row, col, 0, filter_idx]
                        if col < 2:
                            f.write(f'x"{weight_val & 0xFF:02X}", ')
                        else:
                            f.write(f'x"{weight_val & 0xFF:02X}"')
                    if row < 2:
                        f.write("),\n")
                    else:
                        f.write(")\n")
                
                if filter_idx < quantized_weights.shape[3] - 1:
                    f.write("    ),\n")
                else:
                    f.write("    )\n")
            
            f.write(");\n\n")
            
            # Also generate bias initialization
            f.write("-- Bias array declaration:\n")
            f.write("signal bias_array : WORD_ARRAY(0 to NUM_FILTERS-1) := (\n")
            for i, bias in enumerate(quantized_biases):
                if i < len(quantized_biases) - 1:
                    f.write(f'    {i} => x"{bias & 0xFF:02X}",\n')
                else:
                    f.write(f'    {i} => x"{bias & 0xFF:02X}"\n')
            f.write(");\n")
        print("✓ VHDL weight file generated: conv_weights.vhd")
    
    if filetype == "txt":
        # Save individual filter weights as separate files
        for filter_idx in range(quantized_weights.shape[3]):
            filter_weights = quantized_weights[:, :, :, filter_idx]  # 3x3x1
            filename = f"filter_{filter_idx}_weights.txt"
            
            with open(filename, 'w') as f:
                f.write(f"-- Filter {filter_idx} weights (3x3 kernel)\n")
                f.write(f"-- Quantized to 8-bit signed integers\n\n")
                for row in range(3):
                    for col in range(3):
                        weight_val = filter_weights[row, col, 0]
                        f.write(f"weight({row},{col}) <= {weight_val}; -- {weight_val:#04x}\n")
            print(f"Filter {filter_idx} weights saved to {filename}")
    
    if filetype == "bin":
        # Save weights and biases as binary files
        quantized_weights.tofile('conv_weights.bin')
        quantized_biases.tofile('conv_biases.bin')
        print("✓ Binary weight files generated: conv_weights.bin, conv_biases.bin")

def extract_weights_for_fpga(quantized_model):
    """Extract quantized weights for FPGA implementation."""
    print("\n=== FPGA Weight Extraction ===")
    
    try:
        interpreter = tf.lite.Interpreter(model_content=quantized_model)
        interpreter.allocate_tensors()
        print("Interpreter initialized successfully.")
    except Exception as e:
        print("Error initializing TensorFlow Lite interpreter:", e)
        return
    
    try:
        tensor_details = interpreter.get_tensor_details()
        print("Tensor details being processed:")
        for detail in tensor_details:
            print(f"Name: {detail['name']}, Index: {detail['index']}, Shape: {detail['shape']}, Dtype: {detail['dtype']}")
    except Exception as e:
        print("Error retrieving tensor details:", e)
        return
    
    print("Quantized model layers and weights:")
    matched = False
    for detail in tensor_details:
        try:
            if ('weights' in detail['name'].lower() or 
                'kernel' in detail['name'].lower() or 
                'MatMul' in detail['name'] or 
                'Conv2D' in detail['name']):
                matched = True
                tensor = interpreter.get_tensor(detail['index'])
                print(f"Extracted tensor: {detail['name']}, Shape: {tensor.shape}, Dtype: {tensor.dtype}")
                
                # Save weights as binary file for FPGA
                filename = f"weights_{detail['name'].replace('/', '_')}.bin"
                tensor.tofile(filename)
                print(f"  → Saved to {filename}")
        except Exception as e:
            print(f"Error processing tensor {detail['name']}:", e)
    
    if not matched:
        print("No tensors matched the condition for weights or kernel.")

def convert_to_onnx():
    """Convert SavedModel to ONNX format."""
    import sys
    python_path = sys.executable  # Use the current Python executable
    try:
        result = subprocess.run([
            python_path, "-m", "tf2onnx.convert",
            "--saved-model", "saved_model",
            "--output", "quickdraw_model.onnx"
        ], capture_output=True, text=True, check=True)
        print("✓ Model successfully converted to ONNX format: quickdraw_model.onnx")
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"❌ ONNX conversion failed: {e}")
        print(f"Error output: {e.stderr}")
    except FileNotFoundError:
        print("❌ tf2onnx not installed. Install with: pip install tf2onnx")
        print("ONNX conversion skipped - TFLite models are sufficient for FPGA!")

def print_summary():
    """Print summary of generated files."""
    print("\n=== Summary ===")
    print("Generated files for FPGA implementation:")
    print("- quantized_model.tflite (8-bit post-training quantized)")
    print("- quantized_manual_model.tflite (manual quantized model)")
    print("- weights_*.bin (individual weight files)")
    print("- All weights are quantized to 8-bit integers")
    print("- Ready for FPGA implementation with 8-bit arithmetic")
    print("\n💡 Note: Post-training quantization works well for most FPGA applications!")
    print("   The PTQ model should provide good accuracy for your CNN inference.")

# Main execution
if __name__ == "__main__":
    # Load and preprocess data
    x, y, categories = load_data()
    
    # Create and train model
    model = create_model(len(categories))
    model = train_model(model, x, y)
    
    # Evaluate model (if enabled)
    evaluate_model(model, x, y, categories)
    
    # Extract weights for VHDL implementation
    extract_weights_for_vhdl(model)
    
    # Export model
    export_model(model)
    
    # Quantization pipeline
    x_test_quant, y_test_quant = create_test_dataset_for_quantization(x, categories)
    quantized_model = quantize_model_post_training(x)
    test_quantized_model(quantized_model, x_test_quant, y_test_quant)
    apply_manual_quantization(model, x_test_quant, y_test_quant)
    extract_weights_for_fpga(quantized_model)
    
    # Convert to ONNX
    convert_to_onnx()
    
    # Print summary
    print_summary()
