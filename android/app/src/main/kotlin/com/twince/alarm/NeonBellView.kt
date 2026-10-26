package com.twince.alarm

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator

/** Pulsing cyan bell used on the lock-screen alarm. */
class NeonBellView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {
    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1800L
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener { invalidate() }
    }

    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val wavePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        color = Color.parseColor("#7EEBFF")
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!animator.isStarted) animator.start()
    }

    override fun onDetachedFromWindow() {
        animator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f + dp(6f)
        val phase = (animator.animatedValue as? Float) ?: 0f
        drawHalo(canvas, cx, cy)
        drawWaves(canvas, cx, cy, phase, -1)
        drawWaves(canvas, cx, cy, phase, 1)
        drawBell(canvas, cx, cy)
    }

    private fun drawHalo(canvas: Canvas, cx: Float, cy: Float) {
        val radius = dp(108f)
        glowPaint.shader = RadialGradient(
            cx,
            cy,
            radius,
            intArrayOf(Color.parseColor("#663DDCFF"), Color.parseColor("#22315CFF"), Color.TRANSPARENT),
            floatArrayOf(0.05f, 0.42f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(cx, cy, radius, glowPaint)
    }

    private fun drawWaves(canvas: Canvas, cx: Float, cy: Float, phase: Float, side: Int) {
        for (index in 0 until 3) {
            val progress = (phase + index * 0.28f) % 1f
            val spread = dp(14f) + progress * dp(38f)
            val alpha = ((1f - progress) * 220f).toInt().coerceIn(0, 220)
            wavePaint.color = Color.argb(alpha, 125, 230, 255)
            wavePaint.strokeWidth = dp(2.4f)
            val anchorX = cx + side * dp(50f)
            val oval = RectF(
                anchorX - spread,
                cy - spread * 0.95f,
                anchorX + spread,
                cy + spread * 0.7f,
            )
            val start = if (side < 0) 118f else -58f
            canvas.drawArc(oval, start, 74f, false, wavePaint)
        }
    }

    private fun drawBell(canvas: Canvas, cx: Float, cy: Float) {
        val radius = dp(32f)
        val top = cy - dp(36f)
        val bottom = cy + dp(20f)
        val dome = RectF(cx - radius, top, cx + radius, top + radius * 2.15f)
        val body = Path().apply {
            arcTo(dome, 206f, 128f, true)
            lineTo(cx + radius + dp(10f), bottom)
            lineTo(cx - radius - dp(10f), bottom)
            close()
        }
        strokePaint.style = Paint.Style.STROKE
        for (layer in 8 downTo 1) {
            strokePaint.strokeWidth = dp(layer * 2.1f)
            strokePaint.alpha = 16 + layer
            canvas.drawPath(body, strokePaint)
        }
        fillPaint.shader = LinearGradient(
            cx,
            top,
            cx,
            bottom + dp(8f),
            intArrayOf(Color.WHITE, Color.parseColor("#B8F4FF"), Color.parseColor("#3D8BFF")),
            floatArrayOf(0f, 0.42f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawPath(body, fillPaint)
        fillPaint.shader = null
        fillPaint.color = Color.parseColor("#E8FBFF")
        canvas.drawRoundRect(
            cx - dp(3.2f),
            top - dp(9f),
            cx + dp(3.2f),
            top + dp(8f),
            dp(3f),
            dp(3f),
            fillPaint,
        )
        canvas.drawRoundRect(
            cx - radius - dp(10f),
            bottom - dp(3f),
            cx + radius + dp(10f),
            bottom + dp(7f),
            dp(6f),
            dp(6f),
            fillPaint,
        )
        fillPaint.color = Color.parseColor("#7EEBFF")
        canvas.drawCircle(cx, bottom + dp(16f), dp(5.5f), fillPaint)
    }

    private fun dp(value: Float): Float = value * resources.displayMetrics.density
}
