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
TEST_ENABLED = True  # Set to False to skip visualizations for faster execution

def load_data():
    """Load and preprocess data from training folder."""
    print("Loading data...")
    
    # Dynamically load categories from the training_data folder (sorted for deterministic indices)
    categories = sorted([os.path.splitext(file)[0] for file in os.listdir(TRAINING_DATA_FOLDER) if file.endswith(".npy")])
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
    
    # Shuffle data to ensure good distribution for train/test splits
    # Use stratified shuffle: shuffle within each class to maintain class structure
    shuffled_data = []
    shuffled_labels = []
    np.random.seed(42)  # Set seed for reproducibility
    
    for i in range(len(categories)):
        # Get indices for this class
        class_mask = (y == i)
        class_x = x[class_mask]
        class_y = y[class_mask]
        
        # Shuffle within this class
        class_indices = np.arange(len(class_x))
        np.random.shuffle(class_indices)
        
        shuffled_data.append(class_x[class_indices])
        shuffled_labels.append(class_y[class_indices])
    
    x = np.concatenate(shuffled_data)
    y = np.concatenate(shuffled_labels)
    print(f'Data shuffled within each class for better distribution')
    
    # Preprocess data - NO NORMALIZATION (train on raw [0-255] to match VHDL)
    x = x.reshape(-1, 28, 28, 1).astype('float32')  # Keep raw pixel values
    y = to_categorical(y, num_classes=len(categories))
    print('⚠️  Training on RAW [0-255] pixel values (matching VHDL implementation)')
    
    return x, y, categories
    
def create_model(num_classes):
    """Create and compile the CNN model."""
    print("Creating model...")
    
    model = Sequential([
        Conv2D(32, (3,3), activation='relu', input_shape=(28,28,1)),
        MaxPooling2D(2,2),
        Conv2D(64, (3,3), activation='relu'),
        MaxPooling2D(2,2),
        Flatten(),
        Dense(128, activation='relu'),
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
    
    # Model trained on RAW [0-255] inputs - no normalization needed!
    test_image_raw = test_image.astype(np.float32)  # Keep raw values
    sample_input = np.expand_dims(np.expand_dims(test_image_raw, 0), -1)  # Add batch and channel dims
    print(f"Using VHDL-compatible test pattern (28x28)")
    print(f"Input range: [{sample_input.min():.1f}, {sample_input.max():.1f}] (raw pixel values)")
    
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
            # Save ALL filter outputs (not just first 3)
            for filter_idx in range(output.shape[-1]):
                filter_output = output[0, :, :, filter_idx]
                # Only print first 3 for readability
                if filter_idx < 3:
                    print(f"  Filter {filter_idx} output (5x5 region):")
                    for row in range(min(5, filter_output.shape[0])):
                        row_str = ""
                        for col in range(min(5, filter_output.shape[1])):
                            row_str += f"{filter_output[row,col]:8.3f} "
                        print(f"    {row_str}")
                
                # Save complete filter output for ALL filters
                intermediate_data[f"layer_{i}_filter_{filter_idx}"] = filter_output
            
            print(f"  ✓ Saved all {output.shape[-1]} filter outputs")
        
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
    # Use model.save() to preserve Keras metadata (needed for reload and FPGA export)
    try:
        # Save in Keras format with SavedModel structure
        model.save("model/saved_model", save_format='tf')
        print("✓ Model exported as SavedModel at 'model/saved_model'.")
    except Exception as e:
        print(f"Warning: Failed to save model: {e}")
        # Fallback to the Keras HDF5 format
        model.save("model/saved_model_h5.h5")
        print("✓ Model exported with fallback to Keras H5 at 'model/saved_model_h5.h5'.")

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
        # Prepare input according to interpreter quantization parameters if available
        test_input = x_test_quant[i:i+1].astype(np.float32)
        # If input is already in [0,255] raw pixel range, keep as is; otherwise assume 0-1
        # Use scale and zero_point from the interpreter if present
        in_detail = input_details[0]
        if 'quantization' in in_detail and in_detail['quantization'] is not None:
            scale, zero_point = in_detail['quantization']
            if scale and zero_point is not None:
                # Map float input to int8 using (x / scale) + zero_point
                q = np.round(test_input / scale + zero_point).astype(in_detail['dtype'])
            else:
                # Fallback: center around zero for uint8/int8 mapping
                q = np.clip(test_input - 128, -128, 127).astype(in_detail['dtype'])
        else:
            # No quantization info; attempt a reasonable mapping: center and clip
            q = np.clip(test_input - 128, -128, 127).astype(in_detail['dtype'])
        interpreter.set_tensor(in_detail['index'], q)
        interpreter.invoke()
        
        quantized_output = interpreter.get_tensor(output_details[0]['index'])
        predicted_class_quantized = np.argmax(quantized_output)
        
        if predicted_class_quantized == y_test_quant[i]:
            correct_predictions += 1
    
    accuracy = correct_predictions / len(x_test_quant)
    print(f"Quantized model accuracy on {len(x_test_quant)} samples: {accuracy:.3f} ({accuracy*100:.1f}%)")

def apply_manual_quantization(model, x_test_quant, y_test_quant):
    """Apply manual quantization simulation for FPGA compatibility using Q1.6 format."""
    print("\n=== Manual Quantization Simulation (Q1.6 Format) ===")
    
    # Q1.6 format parameters (must match export_to_FPGA)
    fractional_bits = 6
    scale_factor = 2 ** fractional_bits  # 64
    max_value = 2.0 - (1.0 / scale_factor)  # ~1.984375
    min_value = -2.0
    
    print("Applying Q1.6 quantization simulation (matching FPGA export)...")
    
    manual_quant_model = tf.keras.models.clone_model(model)
    manual_quant_model.set_weights(model.get_weights())
    
    # Simulate Q1.6 quantization (same as FPGA export)
    quantized_weights = []
    for layer_weights in manual_quant_model.get_weights():
        # Clamp to Q1.6 range
        clamped = np.clip(layer_weights, min_value, max_value)
        # Quantize: scale to int8, then scale back
        quantized_int = np.round(clamped * scale_factor)
        quantized = quantized_int / scale_factor
        quantized_weights.append(quantized.astype(np.float32))
    
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
    """ Export model weights and biases for each layer to .txt files for FPGA use 
    
    NOTE: This model is NOW trained on RAW [0,255] inputs to match VHDL implementation.
    No scaling adjustments needed during export.
    """
    print(f"\n=== Exporting Weights and Biases to FPGA ({q_format} format) ===")
    print("✓ Model trained on RAW [0-255] inputs (matching VHDL implementation)")
    
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
        # Ensure we operate on Python ints (handle numpy types)
        try:
            iv = int(value)
        except Exception:
            iv = 0
        if iv < 0:
            return f"{(256 + iv) & 0xFF:02X}"
        else:
            return f"{iv & 0xFF:02X}"
    
    # Create output directory
    output_dir = "model/fpga_weights_and_bias"
    os.makedirs(output_dir, exist_ok=True)
    
    layer_count = 0
    total_params = 0
    # Collect quantized biases per layer to emit a single VHDL package
    bias_collections = {}
    
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
                    
                    # Determine memory organization based on layer type
                    if len(weights.shape) == 4:  # Conv2D: (kernel_h, kernel_w, in_channels, num_filters)
                        kernel_h, kernel_w, in_channels, num_filters = weights.shape
                        f.write(f"; Memory organization: {kernel_h}x{kernel_w}x{in_channels} addresses × {num_filters*8} bits (packed)\n")
                        f.write(f"; Each address contains all {num_filters} filter weights for one (kernel_pos, channel) combination\n")
                    elif len(weights.shape) == 2:  # Dense: (inputs, outputs)
                        num_inputs, num_outputs = weights.shape
                        f.write(f"; Memory organization: {num_inputs} addresses × {num_outputs*8} bits (packed)\n")
                        f.write(f"; Each address contains all {num_outputs} node weights for one input\n")
                    f.write(f";\n")
                    
                    # Proper COE format keywords
                    f.write(f"memory_initialization_radix=16; Hexadecimal format\n")
                    f.write(f"memory_initialization_vector=")
                    
                    # Pack weights for Conv2D layers
                    if len(weights.shape) == 4:  # Conv2D
                        kernel_h, kernel_w, in_channels, num_filters = weights.shape
                        depth = kernel_h * kernel_w * in_channels
                        
                        # Reshape: (K_H, K_W, C_in, N_filters) -> pack by kernel position and channel
                        # For each combination of (kernel_h, kernel_w, channel), pack all filters together
                        for addr in range(depth):
                            # Calculate position in 3D space (kh, kw, c_in)
                            kh = addr // (kernel_w * in_channels)
                            kw = (addr // in_channels) % kernel_w
                            c_in = addr % in_channels
                            
                            # Pack all num_filters weights at this (kh, kw, c_in) position into one wide word
                            packed_value = 0
                            for f_idx in range(num_filters):
                                # Calculate correct index in flattened array
                                # TensorFlow weight shape: (kernel_h, kernel_w, in_channels, num_filters)
                                weight_idx = ((kh * kernel_w + kw) * in_channels + c_in) * num_filters + f_idx
                                qw = quantized_weights[weight_idx]
                                byte_value = int(qw) & 0xFF
                                # Pack MSB-first so that filter 0 occupies the most significant byte
                                # This matches the VHDL BRAM unpacking convention (MSB-first)
                                packed_value |= (byte_value << ((num_filters - 1 - f_idx) * 8))
                            
                            # Write packed value
                            num_hex_chars = (num_filters * 8 + 3) // 4
                            if addr == 0:
                                f.write(f"{packed_value:0{num_hex_chars}X}")
                            elif addr == depth - 1:
                                f.write(f",{packed_value:0{num_hex_chars}X};")
                            else:
                                f.write(f",{packed_value:0{num_hex_chars}X}")
                            
                            # Add newline for readability
                            if (addr + 1) % 4 == 0 and addr != depth - 1:
                                f.write("\n")
                        
                        if depth % 4 != 0:
                            f.write("\n")
                    elif len(weights.shape) == 2:  # Dense: (num_inputs, num_outputs)
                        num_inputs, num_outputs = weights.shape
                        depth = num_inputs
                        
                        # Pack weights: for each input, pack all output node weights together
                        # TensorFlow Dense weight shape: (num_inputs, num_outputs)
                        for input_idx in range(depth):
                            # Pack all num_outputs weights for this input into one wide word
                            packed_value = 0
                            for output_idx in range(num_outputs):
                                # Calculate correct index in flattened array
                                weight_idx = input_idx * num_outputs + output_idx
                                qw = quantized_weights[weight_idx]
                                byte_value = int(qw) & 0xFF
                                # Pack MSB-first to match VHDL unpacking: output 0 → MSB, output N-1 → LSB
                                packed_value |= (byte_value << ((num_outputs - 1 - output_idx) * 8))
                            
                            # Write packed value (same format as Conv2D for consistency)
                            num_hex_chars = (num_outputs * 8 + 3) // 4
                            if input_idx == 0:
                                f.write(f"{packed_value:0{num_hex_chars}X}")
                            elif input_idx == depth - 1:
                                f.write(f",{packed_value:0{num_hex_chars}X};")
                            else:
                                f.write(f",{packed_value:0{num_hex_chars}X}")
                            
                            # Add newline for readability every 4 addresses
                            if (input_idx + 1) % 4 == 0 and input_idx != depth - 1:
                                f.write("\n")
                        
                        if depth % 4 != 0:
                            f.write("\n")
                    else:
                        # Other layers: write individual values (unpacked)
                        for j, qw in enumerate(quantized_weights):
                            if j == 0:
                                f.write(f"{int8_to_hex(qw)}")
                            elif j == len(quantized_weights) - 1:
                                f.write(f",{int8_to_hex(qw)};")
                            else:
                                f.write(f",{int8_to_hex(qw)}")
                            
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
                    
                    # Write individual bias values (unpacked format)
                    for j, qb in enumerate(quantized_biases):
                        if j == 0:
                            f.write(f"{int8_to_hex(qb)}")
                        elif j == len(quantized_biases) - 1:
                            f.write(f",{int8_to_hex(qb)};")
                        else:
                            f.write(f",{int8_to_hex(qb)}")
                        
                        # Add newline every 16 values for readability
                        if (j + 1) % 16 == 0 and j != len(quantized_biases) - 1:
                            f.write("\n")
                    
                    # Final newline if not already added
                    if len(quantized_biases) % 16 != 0:
                        f.write("\n")
                
                print(f"  ✓ Biases saved to: {biases_filename}")
                total_params += len(quantized_biases)
                # Store quantized biases for package emission later
                if len(quantized_biases.shape) == 1 or isinstance(quantized_biases, (list, np.ndarray)):
                    key = f"layer_{i}_{layer.name}"
                    # convert to plain Python list of ints
                    bias_collections[key] = [int(x) for x in np.asarray(quantized_biases).flatten().tolist()]
            
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
    # Emit a single VHDL package with all collected bias arrays
    if bias_collections:
        try:
            vhd_path = os.path.join('src', 'convolution_layer', 'bias_pkg.vhd')
            os.makedirs(os.path.dirname(vhd_path), exist_ok=True)
            with open(vhd_path, 'w') as vhd:
                vhd.write("library IEEE;\n")
                vhd.write("use IEEE.STD_LOGIC_1164.ALL;\n")
                vhd.write("use IEEE.NUMERIC_STD.ALL;\n\n")
                vhd.write("package bias_pkg is\n")
                # Write each bias array type and constant
                for idx, (key, vals) in enumerate(bias_collections.items()):
                    n = len(vals)
                    vhd.write(f"    type {key}_t is array(0 to {n-1}) of signed(7 downto 0);\n")
                    vhd.write(f"    constant {key}_BIAS : {key}_t := (\n")
                    for j, val in enumerate(vals):
                        comma = ',' if j < n-1 else ''
                        vhd.write(f"        {j} => to_signed({int(val)}, 8){comma}\n")
                    vhd.write("    );\n")
                vhd.write("end package bias_pkg;\n\n")
                vhd.write("package body bias_pkg is\nend package body bias_pkg;\n")
            print(f"✓ Wrote single VHDL bias package: {vhd_path}")
        except Exception as e:
            print(f"! Failed to write combined bias VHDL package: {e}")

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
