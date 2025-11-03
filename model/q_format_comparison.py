import numpy as np
import tensorflow as tf
try:
    from CNN import load_data, create_model, train_model
except ImportError:
    from .CNN import load_data, create_model, train_model

def simulate_q_format_inference(model, x_test, q_format="Q3.4", verbose=True):
    """Simulate inference with Q-format quantized weights."""
    
    # Parse Q format
    q_parts = q_format.split('.')
    integer_bits = int(q_parts[0][1:])
    fractional_bits = int(q_parts[1])
    total_bits = integer_bits + fractional_bits + 1
    
    q_scale = 2**fractional_bits
    max_q_value = 2**(total_bits-1) - 1
    min_q_value = -2**(total_bits-1)
    
    if verbose:
        print(f"\n=== Simulating {q_format} Format ===")
        print(f"Scale factor: {q_scale}")
        print(f"Value range: [{min_q_value/q_scale:.6f}, {max_q_value/q_scale:.6f}]")
    
    # Create a copy of the model
    quantized_model = tf.keras.models.clone_model(model)
    quantized_model.set_weights(model.get_weights())
    
    # Quantize all layer weights
    quantized_weights = []
    original_weights = model.get_weights()
    total_mse_error = 0
    
    for i, layer_weights in enumerate(original_weights):
        # Quantize to Q format
        q_weights = np.round(layer_weights * q_scale).astype(int)
        q_weights = np.clip(q_weights, min_q_value, max_q_value).astype(int)
        
        # Convert back to float for simulation
        simulated_weights = q_weights / q_scale
        quantized_weights.append(simulated_weights)
        
        if verbose:
            print(f"Layer {i}: Original range [{np.min(layer_weights):.6f}, {np.max(layer_weights):.6f}]")
            print(f"Layer {i}: Quantized range [{np.min(simulated_weights):.6f}, {np.max(simulated_weights):.6f}]")

        # Helpful VHDL-style debug output: hex, binary and signed Q-format for some weights
        def _to_unsigned_twos(val, bits):
            # val is signed integer in range [min_q_value, max_q_value]
            if val < 0:
                return (1 << bits) + int(val)
            return int(val)

        def _int_to_hex(val, bits):
            u = _to_unsigned_twos(val, bits)
            nibbles = (bits + 3) // 4
            fmt = '0x{:0' + str(nibbles) + 'X}'
            return fmt.format(u)

        def _int_to_bin(val, bits):
            u = _to_unsigned_twos(val, bits)
            return format(u, '0{}b'.format(bits))

        def _int_to_q_decimal(val, frac_bits):
            # interpret val as signed integer (already signed), convert to real
            realv = float(val) / (2 ** frac_bits)
            return f"{realv:.3f}"

        if verbose:
            bits = total_bits
            sample = q_weights.flatten()[:8]
            print(f"Layer {i} sample (int -> hex bin q{fractional_bits}):")
            for v in sample:
                print(f"  {int(v):4d} -> {_int_to_hex(int(v), bits)} {_int_to_bin(int(v), bits)} {_int_to_q_decimal(int(v), fractional_bits)}")

            # Also write a per-layer debug file matching VHDL format (one value per line)
            try:
                fname = f"model/vhdl_debug_layer_{i}.txt"
                with open(fname, 'w') as fh:
                    fh.write("# val hex bin q_decimal\n")
                    for v in q_weights.flatten():
                        fh.write(f"{int(v)} {_int_to_hex(int(v), bits)} {_int_to_bin(int(v), bits)} {_int_to_q_decimal(int(v), fractional_bits)}\n")
                if verbose:
                    print(f"Wrote VHDL-style debug file: {fname}")
            except Exception as e:
                if verbose:
                    print(f"Warning: could not write VHDL debug file for layer {i}: {e}")
        
        # Calculate quantization error
        mse_error = np.mean((layer_weights - simulated_weights)**2)
        total_mse_error += mse_error
        
        if verbose:
            print(f"Layer {i}: MSE error: {mse_error:.8f}")
    
    quantized_model.set_weights(quantized_weights)
    
    # Test accuracy
    predictions = quantized_model.predict(x_test[:100], verbose=0)
    predicted_classes = np.argmax(predictions, axis=1)
    
    # Compare with original model
    original_predictions = model.predict(x_test[:100], verbose=0)
    original_classes = np.argmax(original_predictions, axis=1)
    
    agreement = np.mean(predicted_classes == original_classes)
    
    if verbose:
        print(f"Total MSE error: {total_mse_error:.8f}")
        print(f"{q_format} vs Original Model Agreement: {agreement:.3f} ({agreement*100:.1f}%)")
    
    return quantized_model, agreement

def run_multiple_simulations(num_runs=5):
    print(f"=== Q-Format Comparison Analysis ({num_runs} runs for averaging) ===")
    
    # Test different Q formats
    formats_to_test = [
        "Q7.8",   # 16-bit: 7 integer + 8 fractional + 1 sign
        "Q3.4",   # 8-bit:  3 integer + 4 fractional + 1 sign  
        "Q2.5",   # 8-bit:  2 integer + 5 fractional + 1 sign (more precision)
        "Q1.6",   # 8-bit:  1 integer + 6 fractional + 1 sign (max precision)
    ]
    
    # Store results for all runs
    all_results = {fmt: {'accuracies': [], 'agreements': [], 'accuracy_losses': []} 
                   for fmt in formats_to_test}
    original_accuracies = []
    
    for run in range(num_runs):
        print(f"\n{'='*20} RUN {run+1}/{num_runs} {'='*20}")
        
        # Load data and create model (new model each run for variation)
        x, y, categories = load_data()
        model = create_model(len(categories))
        model = train_model(model, x, y)
        
        # Create test set (different random samples each run)
        test_samples_per_class = 20  # Increased for better statistics
        test_indices = []
        np.random.seed(run * 42)  # Different seed each run
        
        for i in range(len(categories)):
            class_start = i * 1000  # SAMPLES_PER_CLASS from CNN.py
            class_end = (i + 1) * 1000
            # Random sampling from each class
            available_indices = np.arange(class_start, class_end)
            selected_indices = np.random.choice(available_indices, 
                                              size=test_samples_per_class, 
                                              replace=False)
            test_indices.extend(selected_indices)
        
        test_indices = np.array(test_indices)
        x_test = x[test_indices]
        y_test = y[test_indices]
        
        # Get original accuracy for this run
        original_predictions = model.predict(x_test, verbose=0)
        original_classes = np.argmax(original_predictions, axis=1)
        true_classes = np.argmax(y_test, axis=1)
        original_accuracy = np.mean(original_classes == true_classes)
        original_accuracies.append(original_accuracy)
        
        print(f"Run {run+1} - Original Model Accuracy: {original_accuracy:.3f} ({original_accuracy*100:.1f}%)")
        
        # Test each Q format
        for q_format in formats_to_test:
            try:
                # Use verbose=False for cleaner output during multiple runs
                quantized_model, agreement = simulate_q_format_inference(model, x_test, q_format, verbose=False)
                
                # Test quantized model accuracy
                quant_predictions = quantized_model.predict(x_test, verbose=0)
                quant_classes = np.argmax(quant_predictions, axis=1)
                quant_accuracy = np.mean(quant_classes == true_classes)
                accuracy_loss = original_accuracy - quant_accuracy
                
                # Store results
                all_results[q_format]['accuracies'].append(quant_accuracy)
                all_results[q_format]['agreements'].append(agreement)
                all_results[q_format]['accuracy_losses'].append(accuracy_loss)
                
                print(f"  {q_format} - Accuracy: {quant_accuracy:.3f}, Loss: {accuracy_loss:+.3f}, Agreement: {agreement:.3f}")
                
            except Exception as e:
                print(f"Error testing {q_format} in run {run+1}: {e}")
                # Add NaN for failed runs
                all_results[q_format]['accuracies'].append(np.nan)
                all_results[q_format]['agreements'].append(np.nan)
                all_results[q_format]['accuracy_losses'].append(np.nan)
    
    return all_results, original_accuracies

def main():
    num_runs = 5  # Number of simulation runs
    all_results, original_accuracies = run_multiple_simulations(num_runs)
    
    # Calculate statistics
    avg_original_accuracy = np.mean(original_accuracies)
    std_original_accuracy = np.std(original_accuracies)
    
    print(f"\n{'='*60}")
    print(f"AVERAGED RESULTS OVER {num_runs} RUNS")
    print(f"{'='*60}")
    print(f"Average Original Model Accuracy: {avg_original_accuracy:.3f} ± {std_original_accuracy:.3f}")
    
    # Calculate averages and statistics for each format
    results_summary = {}
    
    for q_format, results in all_results.items():
        # Filter out NaN values (failed runs)
        valid_accuracies = [x for x in results['accuracies'] if not np.isnan(x)]
        valid_agreements = [x for x in results['agreements'] if not np.isnan(x)]
        valid_losses = [x for x in results['accuracy_losses'] if not np.isnan(x)]
        
        if valid_accuracies:  # Only process if we have valid results
            results_summary[q_format] = {
                'avg_accuracy': np.mean(valid_accuracies),
                'std_accuracy': np.std(valid_accuracies),
                'avg_agreement': np.mean(valid_agreements),
                'std_agreement': np.std(valid_agreements),
                'avg_accuracy_loss': np.mean(valid_losses),
                'std_accuracy_loss': np.std(valid_losses),
                'success_rate': len(valid_accuracies) / num_runs,
                'min_accuracy': np.min(valid_accuracies),
                'max_accuracy': np.max(valid_accuracies)
            }
        else:
            print(f"❌ {q_format}: All runs failed!")
    
    # Display detailed results
    print(f"\n{'Format':<8} {'Avg Acc':<8} {'±Std':<7} {'Avg Loss':<9} {'±Std':<7} {'Agreement':<10} {'Success':<8}")
    print("-" * 70)
    
    for q_format, stats in results_summary.items():
        print(f"{q_format:<8} {stats['avg_accuracy']:.3f}    ±{stats['std_accuracy']:.3f}   "
              f"{stats['avg_accuracy_loss']:+.3f}     ±{stats['std_accuracy_loss']:.3f}   "
              f"{stats['avg_agreement']:.3f}      {stats['success_rate']*100:.0f}%")
    
    # Detailed analysis
    print(f"\nDETAILED ANALYSIS:")
    for q_format, stats in results_summary.items():
        q_parts = q_format.split('.')
        integer_bits = int(q_parts[0][1:])
        fractional_bits = int(q_parts[1])
        total_bits = integer_bits + fractional_bits + 1
        
        print(f"\n{q_format} ({total_bits}-bit):")
        print(f"  • Average accuracy: {stats['avg_accuracy']:.3f} ± {stats['std_accuracy']:.3f}")
        print(f"  • Accuracy range: [{stats['min_accuracy']:.3f}, {stats['max_accuracy']:.3f}]")
        print(f"  • Average loss: {stats['avg_accuracy_loss']:.3f} ± {stats['std_accuracy_loss']:.3f}")
        print(f"  • Model agreement: {stats['avg_agreement']:.3f} ± {stats['std_agreement']:.3f}")
        print(f"  • Success rate: {stats['success_rate']*100:.0f}%")
    
    # Find best formats
    if results_summary:
        # Best overall (lowest average accuracy loss)
        best_overall = min(results_summary.items(), key=lambda x: x[1]['avg_accuracy_loss'])
        
        # Best 8-bit format
        eight_bit_formats = {k: v for k, v in results_summary.items() 
                           if k != "Q7.8" and v['success_rate'] == 1.0}
        
        print(f"\nRECOMMENDations:")
        print(f"Best Overall: {best_overall[0]}")
        print(f"   Average accuracy loss: {best_overall[1]['avg_accuracy_loss']:.3f} +/- {best_overall[1]['std_accuracy_loss']:.3f}")
        print(f"   Consistency: +/-{best_overall[1]['std_accuracy_loss']:.3f} standard deviation")
        
        if eight_bit_formats:
            best_8bit = min(eight_bit_formats.items(), key=lambda x: x[1]['avg_accuracy_loss'])
            print(f"\nBest 8-bit Format: {best_8bit[0]}")
            print(f"   Average accuracy loss: {best_8bit[1]['avg_accuracy_loss']:.3f} +/- {best_8bit[1]['std_accuracy_loss']:.3f}")
            print(f"   Hardware savings: 50% memory vs 16-bit")
            print(f"   Consistency: +/-{best_8bit[1]['std_accuracy_loss']:.3f} standard deviation")
            
            # Stability analysis
            most_stable_8bit = min(eight_bit_formats.items(), key=lambda x: x[1]['std_accuracy_loss'])
            if most_stable_8bit[0] != best_8bit[0]:
                print(f"\nMost Stable 8-bit Format: {most_stable_8bit[0]}")
                print(f"   Lowest variance: +/-{most_stable_8bit[1]['std_accuracy_loss']:.3f}")
        
        # Statistical significance test
        print(f"\nSTATISTICAL CONFIDENCE:")
        for q_format, stats in results_summary.items():
            confidence_interval = 1.96 * stats['std_accuracy_loss'] / np.sqrt(num_runs)  # 95% CI
            print(f"   {q_format}: Loss {stats['avg_accuracy_loss']:.3f} +/- {confidence_interval:.3f} (95% CI)")
    
    print(f"\nNote: Results averaged over {num_runs} independent training runs for statistical reliability.")
    
    # Save results to file
    save_results_to_file(results_summary, num_runs, avg_original_accuracy, std_original_accuracy)

def save_results_to_file(results_summary, num_runs, avg_original_accuracy, std_original_accuracy):
    """Save the comparison results to a text file."""
    filename = "model/q_format_comparison_results.txt"
    
    with open(filename, 'w') as f:
        f.write("Q-Format Comparison Results\n")
        f.write("="*50 + "\n\n")
        f.write(f"Analysis Date: {np.datetime64('today')}\n")
        f.write(f"Number of simulation runs: {num_runs}\n")
        f.write(f"Average original accuracy: {avg_original_accuracy:.3f} ± {std_original_accuracy:.3f}\n\n")
        
        f.write("Detailed Results:\n")
        f.write("-" * 30 + "\n")
        f.write(f"{'Format':<8} {'Avg Acc':<8} {'±Std':<7} {'Avg Loss':<9} {'±Std':<7} {'Agreement':<10}\n")
        f.write("-" * 70 + "\n")
        
        for q_format, stats in results_summary.items():
            f.write(f"{q_format:<8} {stats['avg_accuracy']:.3f}    ±{stats['std_accuracy']:.3f}   "
                   f"{stats['avg_accuracy_loss']:+.3f}     ±{stats['std_accuracy_loss']:.3f}   "
                   f"{stats['avg_agreement']:.3f}\n")
        
        # Find recommendations
        best_overall = min(results_summary.items(), key=lambda x: x[1]['avg_accuracy_loss'])
        eight_bit_formats = {k: v for k, v in results_summary.items() 
                           if k != "Q7.8" and v['success_rate'] == 1.0}
        
        f.write(f"\nRecommendations:\n")
        f.write(f"Best Overall: {best_overall[0]} (loss: {best_overall[1]['avg_accuracy_loss']:+.3f})\n")
        
        if eight_bit_formats:
            best_8bit = min(eight_bit_formats.items(), key=lambda x: x[1]['avg_accuracy_loss'])
            f.write(f"Best 8-bit: {best_8bit[0]} (loss: {best_8bit[1]['avg_accuracy_loss']:+.3f})\n")
    
    print(f"Results saved to: {filename}")


if __name__ == "__main__":
    main()