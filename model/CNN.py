import os
import numpy as np
import tensorflow as tf
from tensorflow.keras.utils import to_categorical
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Conv2D, MaxPooling2D, Flatten, Dense
import subprocess

############### GUIDE ################
# This script builds, trains, and evaluates a CNN model for FPGA implementation.
# It creates quantized models suitable for hardware deployment and generates
# intermediate values for VHDL testbench validation.
############### USE #################

# Install required packages:
# pip install tensorflow matplotlib seaborn scikit-learn

######################################

# Configuration
TRAINING_DATA_FOLDER = "model/training_data"
EPOCHS = 5
BATCH_SIZE = 128
SAMPLES_PER_CLASS = 1000
TEST_ENABLED = False  # Set to False to skip visualizations for faster execution

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

def capture_intermediate_values(model, x_sample, categories):
    """Capture intermediate values from each layer for debugging."""
    print("\n=== Capturing Intermediate Values ===")
    
    # Create the same 28x28 test pattern as used in VHDL testbench
    def create_test_image_28x28():
        test_image = np.zeros((28, 28), dtype=np.uint8)
        for i in range(28):
            for j in range(28):
                test_image[i, j] = (i + j + 1) % 256  # Matches VHDL: (row + col + 1) mod 256
        return test_image
    
    # Use the same test pattern as VHDL instead of training data
    test_image = create_test_image_28x28()
    
    test_image_normalized = test_image.astype(np.float32) / 255.0  # Normalize to [0,1] range
    sample_input = np.expand_dims(np.expand_dims(test_image_normalized, 0), -1)  # Add batch and channel dims
    print(f"Using VHDL-compatible test pattern (28x28)")
    
    # Create a model that outputs intermediate values
    layer_outputs = [layer.output for layer in model.layers]
    intermediate_model = tf.keras.Model(inputs=model.input, outputs=layer_outputs)
    intermediate_outputs = intermediate_model.predict(sample_input)
    
    print(f"Input shape: {sample_input.shape}")
    print(f"Input pixel values (first 5x5 region):")
    input_2d = sample_input[0, :, :, 0]
    for i in range(min(5, input_2d.shape[0])):
        row_str = ""
        for j in range(min(5, input_2d.shape[1])):
            row_str += f"{input_2d[i,j]:6.3f} "
        print(f"  {row_str}")
    
    # Save intermediate values
    intermediate_data = {}
    
    for i, (layer, output) in enumerate(zip(model.layers, intermediate_outputs)):
        print(f"\nLayer {i}: {layer.name} ({layer.__class__.__name__})")
        print(f"  Output shape: {output.shape}")
        
        if isinstance(layer, tf.keras.layers.Conv2D):
            print(f"  Conv2D filters: {layer.filters}, kernel_size: {layer.kernel_size}")
            # Save first few filter outputs
            for filter_idx in range(min(3, output.shape[-1])):
                filter_output = output[0, :, :, filter_idx]
                print(f"  Filter {filter_idx} output (5x5 region):")
                for row in range(min(5, filter_output.shape[0])):
                    row_str = ""
                    for col in range(min(5, filter_output.shape[1])):
                        row_str += f"{filter_output[row,col]:8.3f} "
                    print(f"    {row_str}")
                
                # Save complete filter output
                intermediate_data[f"layer_{i}_filter_{filter_idx}"] = filter_output
        
        elif isinstance(layer, tf.keras.layers.MaxPooling2D):
            print(f"  MaxPooling2D pool_size: {layer.pool_size}")
            # Show first filter after pooling
            pooled_output = output[0, :, :, 0]
            print(f"  Pooled output (first filter, 5x5 region):")
            for row in range(min(5, pooled_output.shape[0])):
                row_str = ""
                for col in range(min(5, pooled_output.shape[1])):
                    row_str += f"{pooled_output[row,col]:8.3f} "
                print(f"    {row_str}")
        
        elif isinstance(layer, tf.keras.layers.Flatten):
            print(f"  Flattened to: {output.shape[1]} values")
            print(f"  First 10 values: {output[0, :10]}")
        
        elif isinstance(layer, tf.keras.layers.Dense):
            print(f"  Dense units: {layer.units}")
            print(f"  Output values: {output[0, :min(10, output.shape[1])]}")
        
        # Store output for comparison
        intermediate_data[f"layer_{i}_output"] = output[0]
    
    # Save intermediate data to files
    np.savez('model/intermediate_values.npz', **intermediate_data)
    print(f"\n✓ Intermediate values saved to 'model/intermediate_values.npz'")
    
    return intermediate_data

def evaluate_model(model, x, y, categories):
    """Evaluate model with visualizations and metrics."""
    print("Evaluating model...")
    
    # Always capture intermediate values for FPGA development
    capture_intermediate_values(model, x, categories)
    
    if not TEST_ENABLED:
        print("ℹ️ Visualization tests skipped (TEST_ENABLED=False)")
        return
        
    # Import visualization libraries only when needed
    try:
        import matplotlib.pyplot as plt
        from sklearn.metrics import confusion_matrix, classification_report
        import seaborn as sns
    except ImportError as e:
        print(f"ℹ️ Visualization libraries not available: {e}")
        print("ℹ️ Skipping visualizations (intermediate values still captured)")
        return
    
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
    plt.savefig('model/sample_predictions.png', dpi=150, bbox_inches='tight')
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
    plt.savefig('model/confusion_matrix.png', dpi=150, bbox_inches='tight')
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
        plt.savefig('model/misclassified_examples.png', dpi=150, bbox_inches='tight')
        plt.show()
    
    # Print metrics
    print("\nClassification Report:")
    print(classification_report(true_classes, predicted_classes, target_names=categories))
    
    accuracy = np.mean(predicted_classes == true_classes)
    print(f"\nTest Accuracy: {accuracy:.3f} ({accuracy*100:.1f}%)")
    
    print("\n✓ Visualization files saved:")
    print("  - model/sample_predictions.png")
    print("  - model/confusion_matrix.png") 
    print("  - model/misclassified_examples.png")

def export_model(model):
    """Export model to SavedModel format."""
    print("Exporting model...")
    model.export("model/saved_model")
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
    converter = tf.lite.TFLiteConverter.from_saved_model("model/saved_model")
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
    with open('model/quantized_model.tflite', 'wb') as f:
        f.write(quantized_model)
    
    print("✓ Post-training quantized model saved as 'model/quantized_model.tflite'")
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
    """Apply manual quantization simulation for FPGA compatibility."""
    print("\n=== Manual Quantization Simulation ===")
    
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
    
    with open('model/quantized_manual_model.tflite', 'wb') as f:
        f.write(quantized_manual_model)
    
    print("✓ Manual quantized model saved as 'model/quantized_manual_model.tflite'")

def convert_to_onnx():
    """Convert SavedModel to ONNX format (optional for FPGA development)."""
    import sys
    python_path = sys.executable
    try:
        result = subprocess.run([
            python_path, "-m", "tf2onnx.convert",
            "--saved-model", "model/saved_model",
            "--output", "model/quickdraw_model.onnx"
        ], capture_output=True, text=True, check=True)
        print("✓ Model successfully converted to ONNX format: model/quickdraw_model.onnx")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("ℹ️ ONNX conversion skipped (optional for FPGA development)")

def export_to_FPGA(model, q_format="Q1.6"):
    """ Export model weights and biases for each layer to .txt files for FPGA use """
    print(f"\n=== Exporting Weights and Biases to FPGA ({q_format} format) ===")
    
    # Q1.6 format: 1 sign bit + 6 fractional bits = 7 bits total (signed 8-bit)
    # Range: -2.0 to +1.984375 (step size: 1/64 = 0.015625)
    fractional_bits = 6
    scale_factor = 2 ** fractional_bits  # 64
    max_value = 2.0 - (1.0 / scale_factor)  # ~1.984375
    min_value = -2.0
    
    def quantize_to_q1_6(value):
        """Convert floating point value to Q1.6 format"""
        # Clamp to valid range
        clamped = np.clip(value, min_value, max_value)
        # Scale and round to nearest integer
        quantized_int = np.round(clamped * scale_factor).astype(np.int8)
        return quantized_int
    
    def int8_to_hex(value):
        """Convert signed int8 to 2-character hex string"""
        if value < 0:
            # Two's complement for negative numbers
            return f"{(256 + value):02X}"
        else:
            return f"{value:02X}"
    
    # Create output directory
    output_dir = "model/fpga_weights_and_bias"
    os.makedirs(output_dir, exist_ok=True)
    
    layer_count = 0
    total_params = 0
    
    # Process each layer
    for i, layer in enumerate(model.layers):
        if hasattr(layer, 'get_weights') and layer.get_weights():
            weights_and_biases = layer.get_weights()
            
            print(f"\nLayer {i}: {layer.name} ({layer.__class__.__name__})")
            
            # Process weights (first element)
            if len(weights_and_biases) > 0:
                weights = weights_and_biases[0]
                print(f"  Weights shape: {weights.shape}")
                print(f"  Weight range: [{np.min(weights):.6f}, {np.max(weights):.6f}]")
                
                # Flatten weights for easier processing
                weights_flat = weights.flatten()
                
                # Quantize to Q1.6
                quantized_weights = quantize_to_q1_6(weights_flat)
                
                # Calculate quantization error
                dequantized = quantized_weights.astype(np.float32) / scale_factor
                quantization_error = np.mean(np.abs(weights_flat - dequantized))
                print(f"  Quantization error (MAE): {quantization_error:.6f}")
                
                # Save as COE file for Vivado (proper format)
                weights_filename = f"{output_dir}/layer_{i}_{layer.name}_weights.coe"
                with open(weights_filename, 'w') as f:
                    # COE file header with proper format
                    f.write(f"; Layer {i}: {layer.name} weights ({q_format} format)\n")
                    f.write(f"; Original shape: {weights.shape}\n")
                    f.write(f"; Total elements: {len(quantized_weights)}\n")
                    f.write(f"; Quantization: {fractional_bits} fractional bits\n")
                    f.write(f"; Range: [{min_value}, {max_value}]\n")
                    f.write(f";\n")
                    
                    # Proper COE format keywords
                    f.write(f"memory_initialization_radix=16; Hexadecimal format\n")
                    f.write(f"memory_initialization_vector=")
                    
                    # Write data values
                    for j, qw in enumerate(quantized_weights):
                        if j == 0:
                            f.write(f"{int8_to_hex(qw)}")
                        elif j == len(quantized_weights) - 1:  # Last element
                            f.write(f",{int8_to_hex(qw)};")
                        else:
                            f.write(f",{int8_to_hex(qw)}")
                        
                        # Add newline every 16 values for readability
                        if (j + 1) % 16 == 0 and j != len(quantized_weights) - 1:
                            f.write("\n")
                    
                    if len(quantized_weights) % 16 != 0:
                        f.write("\n")
                
                print(f"  ✓ Weights saved to: {weights_filename}")
                total_params += len(quantized_weights)
            
            # Process biases (second element, if exists)
            if len(weights_and_biases) > 1:
                biases = weights_and_biases[1]
                print(f"  Biases shape: {biases.shape}")
                print(f"  Bias range: [{np.min(biases):.6f}, {np.max(biases):.6f}]")
                
                # Quantize to Q1.6
                quantized_biases = quantize_to_q1_6(biases)
                
                # Calculate quantization error
                dequantized_biases = quantized_biases.astype(np.float32) / scale_factor
                bias_quantization_error = np.mean(np.abs(biases - dequantized_biases))
                print(f"  Bias quantization error (MAE): {bias_quantization_error:.6f}")
                
                # Save as COE file for Vivado (proper format)
                biases_filename = f"{output_dir}/layer_{i}_{layer.name}_biases.coe"
                with open(biases_filename, 'w') as f:
                    # COE file header with proper format
                    f.write(f"; Layer {i}: {layer.name} biases ({q_format} format)\n")
                    f.write(f"; Shape: {biases.shape}\n")
                    f.write(f"; Total elements: {len(quantized_biases)}\n")
                    f.write(f"; Quantization: {fractional_bits} fractional bits\n")
                    f.write(f"; Range: [{min_value}, {max_value}]\n")
                    f.write(f";\n")
                    
                    # Proper COE format keywords
                    f.write(f"memory_initialization_radix=16; Hexadecimal format\n")
                    f.write(f"memory_initialization_vector=")
                    
                    # Write data values
                    for j, qb in enumerate(quantized_biases):
                        if j == 0:
                            f.write(f"{int8_to_hex(qb)}")
                        elif j == len(quantized_biases) - 1:  # Last element
                            f.write(f",{int8_to_hex(qb)};")
                        else:
                            f.write(f",{int8_to_hex(qb)}")
                        
                        # Add newline every 16 values for readability
                        if (j + 1) % 16 == 0 and j != len(quantized_biases) - 1:
                            f.write("\n")
                    
                    if len(quantized_biases) % 16 != 0:
                        f.write("\n")
                
                print(f"  ✓ Biases saved to: {biases_filename}")
                total_params += len(quantized_biases)
            
            layer_count += 1
    
    # Create summary file
    summary_filename = f"{output_dir}/fpga_export_summary.txt"
    with open(summary_filename, 'w') as f:
        f.write(f"FPGA Weight Export Summary\n")
        f.write(f"========================\n\n")
        f.write(f"Quantization Format: {q_format}\n")
        f.write(f"Fractional Bits: {fractional_bits}\n")
        f.write(f"Scale Factor: {scale_factor}\n")
        f.write(f"Value Range: [{min_value}, {max_value}]\n")
        f.write(f"Step Size: {1.0/scale_factor:.6f}\n\n")
        f.write(f"Total Layers Processed: {layer_count}\n")
        f.write(f"Total Parameters: {total_params}\n\n")
        f.write(f"Files Generated:\n")
        
        for i, layer in enumerate(model.layers):
            if hasattr(layer, 'get_weights') and layer.get_weights():
                f.write(f"  - layer_{i}_{layer.name}_weights.coe\n")
                if len(layer.get_weights()) > 1:
                    f.write(f"  - layer_{i}_{layer.name}_biases.coe\n")
    
    print(f"\n✓ FPGA export complete!")
    print(f"  - {layer_count} layers processed")
    print(f"  - {total_params} parameters exported")
    print(f"  - Files saved in: {output_dir}/")
    print(f"  - Summary: {summary_filename}")
    
    return output_dir

# Main execution
if __name__ == "__main__":
    # Load and preprocess data
    x, y, categories = load_data()
    
    # Create and train model
    model = create_model(len(categories))
    model = train_model(model, x, y)
    
    # Evaluate model (if enabled)
    evaluate_model(model, x, y, categories)
    
    # Export model
    export_model(model)
    
    # Quantization pipeline
    x_test_quant, y_test_quant = create_test_dataset_for_quantization(x, categories)
    quantized_model = quantize_model_post_training(x)
    test_quantized_model(quantized_model, x_test_quant, y_test_quant)
    apply_manual_quantization(model, x_test_quant, y_test_quant)
    
    # Convert to ONNX
    convert_to_onnx()
    
    # Export weights and biases for FPGA
    export_to_FPGA(model)
