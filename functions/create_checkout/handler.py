def create_checkout_handler(event, context):
    try:
        # Extract necessary information from the event
        body = json.loads(event.get('body', '{}'))
        amount = body.get('amount')
        currency = body.get('currency', 'USD')

        # Validate input
        if not amount or not isinstance(amount, (int, float)):
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid amount provided.'})
            }

        # Create a checkout session with Stripe
        session = stripe.checkout.Session.create(
            payment_method_types=['card'],
            line_items=[{
                'price_data': {
                    'currency': currency,
                    'product_data': {
                        'name': 'Sample Product',
                    },
                    'unit_amount': int(amount * 100),  # Convert to cents
                },
                'quantity': 1,
            }],
            mode='payment',
            success_url='https://yourdomain.com/success',
            cancel_url='https://yourdomain.com/cancel',
        )

        # Return the session ID to the client
        return {
            'statusCode': 200,
            'body': json.dumps({'sessionId': session.id})
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }