package com.sih.voicebridge.pipeline

import java.lang.reflect.Constructor
import java.lang.reflect.Field

internal fun classOrNull(className: String): Class<*>? {
    return try {
        Class.forName(className)
    } catch (_: Throwable) {
        null
    }
}

internal fun instantiate(clazz: Class<*>): Any? {
    val constructors = clazz.declaredConstructors.sortedBy { it.parameterCount }
    for (constructor in constructors) {
        val instance = instantiate(constructor)
        if (instance != null) {
            return instance
        }
    }
    return null
}

internal fun instantiate(constructor: Constructor<*>): Any? {
    return try {
        constructor.isAccessible = true
        val args = constructor.parameterTypes.map { defaultValueFor(it) }.toTypedArray()
        constructor.newInstance(*args)
    } catch (_: Throwable) {
        null
    }
}

private fun defaultValueFor(type: Class<*>): Any? {
    return when {
        type == Boolean::class.javaPrimitiveType || type == Boolean::class.java -> false
        type == Int::class.javaPrimitiveType || type == Int::class.java -> 0
        type == Long::class.javaPrimitiveType || type == Long::class.java -> 0L
        type == Float::class.javaPrimitiveType || type == Float::class.java -> 0f
        type == Double::class.javaPrimitiveType || type == Double::class.java -> 0.0
        type == Short::class.javaPrimitiveType || type == Short::class.java -> 0.toShort()
        type == Byte::class.javaPrimitiveType || type == Byte::class.java -> 0.toByte()
        type == Char::class.javaPrimitiveType || type == Char::class.java -> 0.toChar()
        type == String::class.java -> ""
        type.isEnum -> type.enumConstants?.firstOrNull()
        else -> null
    }
}

internal fun requireProperty(target: Any, candidateNames: List<String>, value: Any?) {
    check(setProperty(target, candidateNames, value)) {
        "Cannot configure ${target.javaClass.simpleName}.${candidateNames.joinToString("/")}"
    }
}

internal fun setProperty(target: Any, candidateNames: List<String>, value: Any?): Boolean {
    if (value == null) {
        return false
    }

    for (name in candidateNames) {
        if (setViaSetter(target, name, value)) {
            return true
        }
    }

    for (name in candidateNames) {
        if (setViaField(target, name, value)) {
            return true
        }
    }

    return false
}

private fun setViaSetter(target: Any, propertyName: String, value: Any): Boolean {
    val setterName = "set${propertyName.replaceFirstChar { it.uppercase() }}"
    val methods = target.javaClass.methods.filter { method ->
        method.name.equals(setterName, ignoreCase = true) && method.parameterTypes.size == 1
    }

    for (method in methods) {
        if (!isArgumentCompatible(method.parameterTypes[0], value)) {
            continue
        }

        try {
            method.isAccessible = true
            method.invoke(target, adaptValue(method.parameterTypes[0], value))
            return true
        } catch (_: Throwable) {
        }
    }

    return false
}

private fun setViaField(target: Any, fieldName: String, value: Any): Boolean {
    val field = findField(target.javaClass, fieldName) ?: return false
    return try {
        if (!isArgumentCompatible(field.type, value)) {
            return false
        }
        field.isAccessible = true
        field.set(target, adaptValue(field.type, value))
        true
    } catch (_: Throwable) {
        false
    }
}

internal fun invokeBestMatch(
    target: Any,
    methodNames: List<String>,
    args: List<Any?>,
    staticOnly: Boolean = false,
): Any? {
    val clazz = if (target is Class<*>) target else target.javaClass
    val methods = clazz.methods + clazz.declaredMethods

    for (methodName in methodNames) {
        val candidates = methods.filter { method ->
            method.name.equals(methodName, ignoreCase = true) &&
                (!staticOnly || java.lang.reflect.Modifier.isStatic(method.modifiers)) &&
                method.parameterTypes.size == args.size
        }

        for (method in candidates) {
            val invocationTarget = if (java.lang.reflect.Modifier.isStatic(method.modifiers)) null else target
            if (!areArgumentsCompatible(method.parameterTypes, args)) {
                continue
            }
            try {
                method.isAccessible = true
                val adapted = method.parameterTypes.mapIndexed { index, type ->
                    adaptValue(type, args[index])
                }
                return method.invoke(invocationTarget, *adapted.toTypedArray())
            } catch (_: Throwable) {
            }
        }
    }

    return null
}

private fun findField(clazz: Class<*>, name: String): Field? {
    var current: Class<*>? = clazz
    while (current != null) {
        val field = current.declaredFields.firstOrNull { it.name.equals(name, ignoreCase = true) }
        if (field != null) {
            return field
        }
        current = current.superclass
    }
    return null
}

private fun areArgumentsCompatible(parameterTypes: Array<Class<*>>, args: List<Any?>): Boolean {
    if (parameterTypes.size != args.size) {
        return false
    }

    for (index in parameterTypes.indices) {
        val arg = args[index]
        val type = parameterTypes[index]
        if (arg == null) {
            if (type.isPrimitive) {
                return false
            }
            continue
        }
        if (!isArgumentCompatible(type, arg)) {
            return false
        }
    }

    return true
}

private fun isArgumentCompatible(expectedType: Class<*>, value: Any): Boolean {
    if (expectedType.isAssignableFrom(value.javaClass)) {
        return true
    }

    return when {
        expectedType == Int::class.javaPrimitiveType || expectedType == Int::class.java -> value is Number
        expectedType == Long::class.javaPrimitiveType || expectedType == Long::class.java -> value is Number
        expectedType == Float::class.javaPrimitiveType || expectedType == Float::class.java -> value is Number
        expectedType == Double::class.javaPrimitiveType || expectedType == Double::class.java -> value is Number
        expectedType == Boolean::class.javaPrimitiveType || expectedType == Boolean::class.java -> value is Boolean
        expectedType == String::class.java -> true
        else -> false
    }
}

private fun adaptValue(expectedType: Class<*>, value: Any?): Any? {
    if (value == null) {
        return null
    }

    return when {
        expectedType.isAssignableFrom(value.javaClass) -> value
        expectedType == Int::class.javaPrimitiveType || expectedType == Int::class.java ->
            (value as Number).toInt()

        expectedType == Long::class.javaPrimitiveType || expectedType == Long::class.java ->
            (value as Number).toLong()

        expectedType == Float::class.javaPrimitiveType || expectedType == Float::class.java ->
            (value as Number).toFloat()

        expectedType == Double::class.javaPrimitiveType || expectedType == Double::class.java ->
            (value as Number).toDouble()

        expectedType == String::class.java -> value.toString()
        else -> value
    }
}
